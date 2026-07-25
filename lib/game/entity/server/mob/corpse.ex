defmodule ThistleTea.Game.Entity.Server.Mob.Corpse do
  @moduledoc """
  Corpse phase of a mob's lifecycle: builds the loot session at death (group
  rolls, master loot, round-robin assignment), serves loot interactions, and
  removes the body — on decay, or forced when the respawn comes due. Respawn
  itself lives in `Mob.Respawn`; this module only manages the corpse.
  """
  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.LootRoll
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.Mob.Respawn
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  @dynamic_flag_lootable 0x0001
  @loot_method_round_robin 1
  @loot_method_master_loot 2
  @loot_method_group_loot 3
  @loot_method_need_before_greed 4
  @loot_roll_countdown_ms 60_000
  @pending_remove_retry_ms 10_000
  @roll_type_need 1
  @roll_type_greed 2
  @corpse_decay_ms 300_000
  @corpse_decay_elite_ms 600_000

  def prepare(%Mob{internal: %Internal{loot: %InternalLoot{} = internal_loot} = internal} = state, target) do
    loot = generate_loot(internal_loot, quest_item_filter(state, target))
    session = LootSession.new(loot, internal_loot.tapped_by)

    state =
      state
      |> put_session(session)
      |> setup_group_loot(target)
      |> maybe_set_lootable_flag()

    token = corpse_token(state.internal) + 1
    Process.send_after(self(), {:remove_corpse, token}, decay_ms(internal))

    put_internal_loot(state, %{state.internal.loot | corpse_token: token})
  end

  def removed?(%Mob{internal: %Internal{loot: %InternalLoot{corpse_removed?: removed?}}}), do: removed? == true
  def removed?(%Mob{}), do: false

  def pending?(%Mob{} = state) do
    case session(state) do
      %LootSession{} = session -> LootSession.pending?(session)
      _ -> false
    end
  end

  def remove(%Mob{} = state, token \\ :force) do
    cond do
      not Core.dead?(state) or removed?(state) ->
        state

      token != :force and token != corpse_token(state.internal) ->
        state

      token != :force and pending?(state) ->
        Process.send_after(self(), {:remove_corpse, token}, @pending_remove_retry_ms)
        state

      true ->
        state = resolve_pending_rolls(state)
        close_loot_windows(state)

        Metadata.update(state.object.guid, %{
          tapped_player: nil,
          tapped_group_id: nil,
          loot_projection: nil
        })

        state = Visibility.leave_entity(state)
        World.remove_position(state)

        put_internal_loot(state, %{state.internal.loot | session: nil, corpse_removed?: true})
    end
  end

  def view(%Mob{} = state, %Actor{} = actor) do
    with %LootSession{} = session <- session(state),
         true <- Core.dead?(state) || :no_loot,
         {:ok, %Loot{} = loot} <- LootSession.view(session, actor) do
      state = put_session(state, LootSession.add_viewer(session, actor))
      {{:ok, loot}, state}
    else
      {:error, reason} -> {{:error, reason}, state}
      _ -> {{:error, :no_loot}, state}
    end
  end

  def reserve_item(%Mob{} = state, %Actor{} = actor, slot, owner_pid) when is_pid(owner_pid) do
    reserve(state, owner_pid, &LootSession.reserve_item(&1, actor, slot, &2))
  end

  def take_gold(%Mob{} = state, %Actor{} = actor) do
    with %LootSession{} = session <- session(state),
         {:ok, gold, session} <- LootSession.take_gold(session, actor) do
      {{:ok, gold}, finish_if_done(put_session(state, session))}
    else
      {:error, reason} -> {{:error, reason}, state}
      _ -> {{:error, :no_loot}, state}
    end
  end

  def release(%Mob{} = state, %Actor{} = actor) do
    state =
      case session(state) do
        %LootSession{} = session -> put_session(state, LootSession.remove_viewer(session, actor))
        _ -> state
      end

    finish_if_done(state)
  end

  def master_give(%Mob{} = state, %Actor{} = giver, slot, %Actor{} = recipient) do
    case EntityRegistry.whereis(recipient.guid) do
      pid when is_pid(pid) ->
        case reserve(state, pid, &LootSession.reserve_master(&1, giver, recipient, slot, &2)) do
          {{:ok, %Reservation{} = reservation}, state} ->
            send(pid, {:loot_award, state.object.guid, reservation})
            {:ok, state}

          {_error, state} ->
            {{:error, :invalid}, state}
        end

      _ ->
        {{:error, :invalid}, state}
    end
  end

  def commit(%Mob{} = state, %Commit{} = command) do
    with %LootSession{} = session <- session(state),
         {:ok, %Loot.Item{slot: slot}, session} <- LootSession.commit(session, command) do
      Process.demonitor(command.token, [:flush])
      notify_removed(session, slot)

      state =
        state
        |> put_session(session)
        |> finish_if_done()

      maybe_continue_respawn(state)
      {:ok, state}
    else
      _ -> {{:error, :invalid_reservation}, state}
    end
  end

  def release_reservation(%Mob{} = state, %Release{} = command) do
    with %LootSession{} = session <- session(state),
         {:ok, session} <- LootSession.release(session, command) do
      Process.demonitor(command.token, [:flush])
      state = put_session(state, session)
      maybe_continue_respawn(state)
      {:ok, state}
    else
      _ -> {{:error, :invalid_reservation}, state}
    end
  end

  def reservation_lost(%Mob{} = state, token) when is_reference(token) do
    Process.demonitor(token, [:flush])

    state =
      case session(state) do
        %LootSession{} = session -> put_session(state, LootSession.release(session, token))
        _ -> state
      end

    maybe_continue_respawn(state)
    state
  end

  def roll_vote(%Mob{} = state, voter, slot, vote) do
    with %LootSession{} = session <- session(state),
         {:ok, session, roll} <- LootSession.vote(session, slot, voter, vote) do
      send_vote_echo(state, roll, voter, vote)
      state = put_session(state, session)

      if LootRoll.complete?(roll) do
        resolve_roll(state, slot)
      else
        state
      end
    else
      _ -> state
    end
  end

  def roll_timeout(%Mob{} = state, slot) do
    resolve_roll(state, slot)
  end

  defp close_loot_windows(%Mob{} = state) do
    case session(state) do
      %LootSession{} = session ->
        packet = %Message.SmsgLootReleaseResponse{guid: state.object.guid}
        session |> LootSession.viewers() |> Enum.each(&Network.send_packet(packet, &1))

      _ ->
        :ok
    end
  end

  defp generate_loot(%InternalLoot{} = internal_loot, quest_item_filter) do
    case internal_loot.override do
      %{items: items, gold: gold} ->
        LootLoader.generate_fixed(items, gold)

      _ ->
        LootLoader.generate(internal_loot.id, internal_loot.min_gold, internal_loot.max_gold, quest_item_filter)
    end
  end

  defp quest_item_filter(%Mob{} = state, target) do
    looters = candidate_looters(state, target)

    actors = Enum.map(looters, &ActorFactory.for_guid(&1, state.object.guid))
    fn item_id -> Enum.any?(actors, &Actor.needs_item?(&1, item_id)) end
  end

  defp candidate_looters(%Mob{} = state, target) do
    tapper = tapped_player(state) || target

    case tap_group(state) || killer_group(target) do
      %Party.Group{} = group -> Enum.uniq([tapper | eligible_members(state, group)])
      _ -> [tapper]
    end
    |> Enum.filter(&is_integer/1)
  end

  defp tapped_player(%Mob{internal: %Internal{loot: %InternalLoot{tapped_by: %{player: player}}}}), do: player
  defp tapped_player(%Mob{}), do: nil

  defp setup_group_loot(%Mob{} = state, target) do
    case tap_group(state) || killer_group(target) do
      %Party.Group{} = group -> setup_group_loot_method(state, group)
      _ -> state
    end
  end

  defp setup_group_loot_method(%Mob{} = state, %Party.Group{loot_method: method} = group) do
    state = put_session(state, LootSession.configure_group(session(state), method))

    cond do
      method in [@loot_method_group_loot, @loot_method_need_before_greed] -> start_rolls(state, group)
      method == @loot_method_master_loot -> prepare_master(state, group)
      method == @loot_method_round_robin -> assign_looter(state, group)
      true -> state
    end
  end

  defp start_rolls(%Mob{} = state, group) do
    session = session(state)

    case eligible_members(state, group) do
      [_, _ | _] = eligible ->
        {session, rolls} = LootSession.start_rolls(session, group.loot_threshold, eligible)

        Enum.each(rolls, fn roll ->
          packet = %Message.SmsgLootStartRoll{
            loot_guid: state.object.guid,
            slot: roll.slot,
            item_id: roll.item_id,
            countdown: @loot_roll_countdown_ms
          }

          broadcast_roll_packet(roll, packet)
          Process.send_after(self(), {:loot_roll_timeout, roll.slot}, @loot_roll_countdown_ms)
        end)

        put_session(state, session)

      _ ->
        state
    end
  end

  defp prepare_master(%Mob{} = state, %Party.Group{master_looter: master, loot_threshold: threshold})
       when is_integer(master) and master > 0 do
    put_session(state, LootSession.block_master_items(session(state), master, threshold))
  end

  defp prepare_master(%Mob{} = state, _group), do: state

  defp assign_looter(%Mob{} = state, group) do
    case PartySystem.update_looter(group.id, eligible_members(state, group)) do
      looter when is_integer(looter) ->
        put_session(state, LootSession.assign_looter(session(state), looter))

      _ ->
        state
    end
  end

  defp resolve_pending_rolls(%Mob{} = state) do
    case session(state) do
      %LootSession{rolls: rolls} when map_size(rolls) > 0 ->
        rolls
        |> Map.keys()
        |> Enum.reduce(state, fn slot, state -> resolve_roll(state, slot) end)

      _ ->
        state
    end
  end

  defp resolve_roll(%Mob{} = state, slot) do
    with %LootSession{} = session <- session(state),
         {%LootRoll{} = roll, session} <- LootSession.pop_roll(session, slot) do
      state = put_session(state, session)

      state =
        case LootRoll.resolve(roll) do
          {:won, winner, number, vote, rolled} -> award_roll(state, roll, winner, number, vote, rolled)
          :all_passed -> pass_roll(state, roll)
        end

      state = finish_if_done(state)
      maybe_continue_respawn(state)
      state
    else
      _ -> state
    end
  end

  defp award_roll(%Mob{} = state, roll, winner, number, vote, rolled) do
    type = if vote == :need, do: @roll_type_need, else: @roll_type_greed

    Enum.each(rolled, fn {guid, rolled_number} ->
      broadcast_roll_packet(roll, %Message.SmsgLootRoll{
        loot_guid: state.object.guid,
        slot: roll.slot,
        player_guid: guid,
        item_id: roll.item_id,
        roll_number: rolled_number,
        roll_type: type
      })
    end)

    broadcast_roll_packet(roll, %Message.SmsgLootRollWon{
      loot_guid: state.object.guid,
      slot: roll.slot,
      item_id: roll.item_id,
      winner_guid: winner,
      roll_number: number,
      roll_type: type
    })

    session = session(state)

    winner_actor = ActorFactory.for_guid(winner, state.object.guid)

    case EntityRegistry.whereis(winner) do
      pid when is_pid(pid) ->
        case reserve(state, pid, &LootSession.reserve_roll(&1, winner_actor, roll.slot, &2)) do
          {{:ok, %Reservation{} = reservation}, state} ->
            send(pid, {:loot_award, state.object.guid, reservation})
            state

          {_error, state} ->
            put_session(state, LootSession.unblock_item(session(state), roll.slot))
        end

      _ ->
        put_session(state, LootSession.unblock_item(session, roll.slot))
    end
  end

  defp pass_roll(%Mob{} = state, roll) do
    broadcast_roll_packet(roll, %Message.SmsgLootAllPassed{
      loot_guid: state.object.guid,
      slot: roll.slot,
      item_id: roll.item_id
    })

    put_session(state, LootSession.unblock_item(session(state), roll.slot))
  end

  defp send_vote_echo(%Mob{} = state, roll, voter_guid, vote) do
    {number, type} =
      case vote do
        :pass -> {128, 128}
        :need -> {0, 0}
        :greed -> {128, 2}
      end

    broadcast_roll_packet(roll, %Message.SmsgLootRoll{
      loot_guid: state.object.guid,
      slot: roll.slot,
      player_guid: voter_guid,
      item_id: roll.item_id,
      roll_number: number,
      roll_type: type
    })
  end

  defp broadcast_roll_packet(%LootRoll{eligible: eligible}, packet) do
    Enum.each(eligible, &Network.send_packet(packet, &1))
  end

  defp reserve(%Mob{} = state, owner_pid, reserve_item) do
    case session(state) do
      %LootSession{} = session ->
        token = Process.monitor(owner_pid)

        case reserve_item.(session, token) do
          {:ok, %Reservation{} = reservation, session} ->
            {{:ok, reservation}, put_session(state, session)}

          {:error, reason} ->
            Process.demonitor(token, [:flush])
            {{:error, reason}, state}
        end

      _ ->
        {{:error, :no_loot}, state}
    end
  end

  defp notify_removed(%LootSession{} = session, slot) do
    packet = %Message.SmsgLootRemoved{slot: slot}
    session |> LootSession.viewers() |> Enum.each(&Network.send_packet(packet, &1))
  end

  defp finish_if_done(%Mob{} = state) do
    case session(state) do
      %LootSession{} = session ->
        if LootSession.finished?(session) do
          state = put_session(state, nil)
          state = clear_lootable_flag(state)
          Core.update_object(state, :values) |> World.broadcast_packet(state)
          state
        else
          state
        end

      _ ->
        state
    end
  end

  defp maybe_continue_respawn(%Mob{} = state) do
    Respawn.maybe_continue(state)
  end

  defp maybe_set_lootable_flag(%Mob{unit: %Unit{} = unit} = state) do
    case session(state) do
      %LootSession{loot: %Loot{} = loot} ->
        if Loot.empty?(loot) do
          put_session(state, nil)
        else
          %{state | unit: %{unit | dynamic_flags: (unit.dynamic_flags || 0) ||| @dynamic_flag_lootable}}
        end

      _ ->
        state
    end
  end

  defp clear_lootable_flag(%Mob{unit: %Unit{} = unit} = state) do
    %{state | unit: %{unit | dynamic_flags: (unit.dynamic_flags || 0) &&& bnot(@dynamic_flag_lootable)}}
  end

  defp tap_group(%Mob{internal: %Internal{loot: %InternalLoot{} = internal_loot}}) do
    with %{player: player} <- internal_loot.tapped_by,
         %Party.Group{} = group <- PartySystem.group_of(player) do
      group
    else
      _ -> nil
    end
  end

  defp killer_group(target) when is_integer(target), do: PartySystem.group_of(target)
  defp killer_group(_target), do: nil

  defp eligible_members(%Mob{} = state, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    state
    |> World.nearby_players(Experience.group_reward_distance())
    |> Enum.map(fn {guid, _distance} -> guid end)
    |> Enum.filter(&MapSet.member?(member_guids, &1))
  end

  defp session(%Mob{internal: %Internal{loot: %InternalLoot{session: session}}}), do: session
  defp session(%Mob{}), do: nil

  defp put_session(%Mob{} = state, session) do
    projection = if is_struct(session, LootSession), do: LootSession.project(session)
    Metadata.update(state.object.guid, %{loot_projection: projection})
    put_internal_loot(state, %{state.internal.loot | session: session})
  end

  defp put_internal_loot(%Mob{internal: %Internal{} = internal} = state, %InternalLoot{} = internal_loot) do
    %{state | internal: %{internal | loot: internal_loot}}
  end

  defp corpse_token(%Internal{loot: %InternalLoot{corpse_token: token}}) when is_integer(token), do: token
  defp corpse_token(%Internal{}), do: 0

  defp decay_ms(%Internal{creature: %Creature{rank: rank}}) when not is_nil(rank) do
    if Experience.elite_rank?(rank) do
      @corpse_decay_elite_ms
    else
      @corpse_decay_ms
    end
  end

  defp decay_ms(%Internal{}), do: @corpse_decay_ms
end
