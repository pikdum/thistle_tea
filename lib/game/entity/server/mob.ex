defmodule ThistleTea.Game.Entity.Server.Mob do
  @moduledoc """
  Owning GenServer for a mob: ticks its behavior tree, applies incoming
  attacks and spells through the pure core, and serves loot-window calls.
  """
  use GenServer

  import Bitwise, only: [|||: 2, &&&: 2, bnot: 1]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootRoll
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  @ai_tick_ms 100
  @ai_tick_max_ms 1_000
  @default_respawn_delay_ms 120_000
  @dynamic_flag_lootable 0x0001
  @loot_method_group_loot 3
  @loot_method_need_before_greed 4
  @loot_roll_countdown_ms 60_000
  @roll_type_need 1
  @roll_type_greed 2

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = BT.init(state, MobBT.tree())
    World.update_position(state)
    state = Visibility.join_entity(state)

    schedule_ai_tick(0)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    state = Movement.sync_position(state, Time.now())
    World.update_position(state)
    state = Visibility.refresh_entity(state)

    Core.update_object(state)
    |> Network.send_packet(pid)

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z}, [], Time.now())
    state = EventSink.emit_pending(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, spell}, state) do
    caster_guid = caster_guid(caster)

    state =
      state
      |> maybe_reset_attack_started(caster_guid)
      |> engage_combat(caster_guid)

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = SpellEffect.receive(state, caster, spell, Time.now())

    state =
      state
      |> EventSink.emit(events)
      |> handle_death_transition(target, dead_before)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:receive_heal, amount}, state) do
    state = Core.heal(state, amount)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:loot_roll_vote, voter_guid, slot, vote}, %Mob{internal: %Internal{} = internal} = state) do
    with %LootRoll{} = roll <- Map.get(loot_rolls(internal), slot),
         {:ok, roll} <- LootRoll.vote(roll, voter_guid, vote) do
      send_vote_echo(state, roll, voter_guid, vote)

      rolls = Map.put(loot_rolls(internal), slot, roll)
      state = %{state | internal: Map.put(internal, :loot_rolls, rolls)}
      state = if LootRoll.complete?(roll), do: resolve_loot_roll(state, slot), else: state

      {:noreply, state}
    else
      _ -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:receive_attack, %{caster: caster} = attack}, state) do
    state =
      state
      |> maybe_reset_attack_started(caster)
      |> engage_combat(caster)

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = Combat.receive_attack(state, attack, Time.now())

    state =
      state
      |> handle_death_transition(target, dead_before)
      |> EventSink.emit(events)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_call(:loot_view, _from, %Mob{internal: %Internal{loot: %Loot{} = loot}} = state) do
    if Core.dead?(state) do
      {:reply, {:ok, loot}, state}
    else
      {:reply, {:error, :no_loot}, state}
    end
  end

  def handle_call(:loot_view, _from, state), do: {:reply, {:error, :no_loot}, state}

  def handle_call({:loot_take_item, slot}, _from, %Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state) do
    case Loot.take_item(loot, slot) do
      {:ok, item, loot} -> {:reply, {:ok, item}, %{state | internal: %{internal | loot: loot}}}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:loot_take_item, _slot}, _from, state), do: {:reply, {:error, :no_loot}, state}

  def handle_call({:loot_return_item, slot}, _from, %Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state) do
    {:reply, :ok, %{state | internal: %{internal | loot: Loot.return_item(loot, slot)}}}
  end

  def handle_call({:loot_return_item, _slot}, _from, state), do: {:reply, :ok, state}

  def handle_call(:loot_take_gold, _from, %Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state) do
    case Loot.take_gold(loot) do
      {:ok, gold, loot} -> {:reply, {:ok, gold}, %{state | internal: %{internal | loot: loot}}}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:loot_take_gold, _from, state), do: {:reply, {:error, :no_loot}, state}

  def handle_call(:loot_release, _from, %Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state) do
    state =
      if Loot.empty?(loot) do
        state = %{state | internal: %{internal | loot: nil}}
        state = clear_lootable_flag(state)
        Core.update_object(state, :values) |> World.broadcast_packet(state)
        state
      else
        state
      end

    {:reply, :ok, state}
  end

  def handle_call(:loot_release, _from, state), do: {:reply, :ok, state}

  @impl GenServer
  def handle_info({:loot_roll_timeout, slot}, %Mob{} = state) do
    {:noreply, resolve_loot_roll(state, slot)}
  end

  @impl GenServer
  def handle_info({:deliver_spell, event}, state) do
    EventSink.deliver_spell(event)
    {:noreply, state}
  rescue
    _ -> {:noreply, state}
  end

  @impl GenServer
  def handle_info(:ai_tick, %{internal: %Internal{behavior_tree: behavior_tree}} = state) do
    state = Movement.sync_position(state, Time.now())
    World.update_position(state)
    state = Visibility.refresh_entity(state)
    {status, state} = BT.tick(behavior_tree, state)
    state = EventSink.emit_pending(state)
    schedule_ai_tick(ai_tick_delay(status))
    {:noreply, state, {:continue, :maybe_broadcast}}
  rescue
    _ -> {:noreply, state}
  end

  def handle_info(:respawn, %Mob{} = state) do
    state =
      if Core.dead?(state) do
        state
        |> Mob.respawn()
        |> BT.init(MobBT.tree())
        |> put_spawn_position()
        |> broadcast_respawn()
      else
        clear_respawn_ref(state)
      end

    schedule_ai_tick(0)
    {:noreply, state}
  end

  def handle_info({:event_stop, _event}, state) do
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    {:noreply, state}
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:maybe_broadcast, %{internal: %Internal{broadcast_update?: true}} = state) do
    update_type = if Core.dead?(state), do: :create_object2, else: :values
    Core.update_object(state, update_type) |> World.broadcast_packet(state)
    Metadata.update(state.object.guid, %{alive?: not Core.dead?(state)})
    internal = %{state.internal | broadcast_update?: false}
    {:noreply, %{state | internal: internal}}
  end

  def handle_continue(:maybe_broadcast, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp schedule_ai_tick(delay) when is_integer(delay) and delay >= 0 do
    Process.send_after(self(), :ai_tick, delay)
  end

  defp ai_tick_delay({:running, delay_ms}) when is_integer(delay_ms) and delay_ms >= 0 do
    min(delay_ms, @ai_tick_max_ms)
  end

  defp ai_tick_delay(_status), do: @ai_tick_ms

  defp put_spawn_position(%Mob{} = state) do
    World.update_position(state)
    state = Visibility.join_entity(state)
    update_metadata(state)
    state
  end

  defp broadcast_respawn(%Mob{} = state) do
    Core.update_object(state, :create_object2) |> World.broadcast_packet(state)
    state
  end

  defp engage_combat(%Mob{unit: %Unit{target: current_target} = unit, internal: internal} = state, caster)
       when is_integer(caster) do
    now = Time.now()

    state = update_attacker_count(state, current_target, caster)

    %{
      state
      | unit: %{unit | target: caster},
        internal: %{internal | in_combat: true, last_hostile_time: now}
    }
  end

  defp engage_combat(%Mob{} = state, _caster) do
    state
  end

  defp maybe_reset_attack_started(%Mob{unit: %Unit{target: target}} = state, caster) when is_integer(caster) do
    if target == caster do
      state
    else
      BT.reset_attack_started(state)
    end
  end

  defp maybe_reset_attack_started(state, _caster), do: state

  defp update_attacker_count(%Mob{} = state, current_target, caster) do
    if is_integer(current_target) and current_target > 0 and current_target != caster do
      Metadata.decrement(current_target, :attacker_count, 0)
    end

    if is_integer(caster) and caster > 0 and current_target != caster do
      Metadata.increment(caster, :attacker_count)
    end

    state
  end

  defp update_attacker_count(state, _current_target, _caster), do: state

  defp handle_death_transition(%Mob{} = state, target, false) do
    if Core.dead?(state) do
      state
      |> maybe_decrement_on_death(target)
      |> maybe_reward_kill(target)
      |> generate_loot()
      |> maybe_start_loot_rolls(target)
      |> schedule_respawn()
    else
      state
    end
  end

  defp handle_death_transition(%Mob{} = state, _target, _dead_before), do: state

  defp generate_loot(%Mob{internal: %Internal{} = internal, unit: %Unit{} = unit} = state) do
    loot = LootLoader.generate(internal.loot_id, internal.min_loot_gold, internal.max_loot_gold)

    if Loot.empty?(loot) do
      state
    else
      %{
        state
        | internal: %{internal | loot: loot},
          unit: %{unit | dynamic_flags: (unit.dynamic_flags || 0) ||| @dynamic_flag_lootable}
      }
    end
  end

  defp clear_lootable_flag(%Mob{unit: %Unit{} = unit} = state) do
    %{state | unit: %{unit | dynamic_flags: (unit.dynamic_flags || 0) &&& bnot(@dynamic_flag_lootable)}}
  end

  defp maybe_decrement_on_death(%Mob{} = state, target) when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
    state
  end

  defp maybe_decrement_on_death(%Mob{} = state, _target), do: state

  defp maybe_reward_kill(%Mob{} = state, target) when is_integer(target) and target > 0 do
    if Guid.entity_type(target) == :player do
      case PartySystem.group_of(target) do
        %Party.Group{} = group -> reward_group_kill(state, group)
        _ -> Entity.reward_kill(target, state)
      end
    end

    state
  end

  defp maybe_reward_kill(%Mob{} = state, _target), do: state

  defp reward_group_kill(%Mob{internal: %Internal{} = internal, unit: %Unit{} = unit} = state, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    eligible =
      state
      |> World.nearby_players(Experience.group_reward_distance())
      |> Enum.filter(fn {guid, _distance} -> MapSet.member?(member_guids, guid) end)
      |> Enum.flat_map(fn {guid, _distance} ->
        case Metadata.query(guid, [:level, :alive?]) do
          %{level: level, alive?: true} when is_integer(level) -> [%{guid: guid, level: level}]
          _ -> []
        end
      end)

    opts = [
      experience_multiplier: internal.experience_multiplier,
      extra_flags: internal.extra_flags,
      elite?: Experience.elite_rank?(internal.rank)
    ]

    eligible
    |> Experience.group_shares(unit.level, opts)
    |> Enum.each(fn {guid, xp} -> Entity.reward_kill_share(guid, state, xp) end)
  end

  defp loot_rolls(%Internal{} = internal), do: Map.get(internal, :loot_rolls) || %{}

  defp maybe_start_loot_rolls(%Mob{internal: %Internal{loot: %Loot{} = loot}} = state, target)
       when is_integer(target) and target > 0 do
    with :player <- Guid.entity_type(target),
         %Party.Group{} = group <- PartySystem.group_of(target),
         true <- group.loot_method in [@loot_method_group_loot, @loot_method_need_before_greed],
         [_, _ | _] = eligible <- eligible_rollers(state, group) do
      start_loot_rolls(state, loot, group, eligible)
    else
      _ -> state
    end
  end

  defp maybe_start_loot_rolls(%Mob{} = state, _target), do: state

  defp eligible_rollers(%Mob{} = state, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    state
    |> World.nearby_players(Experience.group_reward_distance())
    |> Enum.map(fn {guid, _distance} -> guid end)
    |> Enum.filter(&MapSet.member?(member_guids, &1))
  end

  defp start_loot_rolls(%Mob{internal: %Internal{} = internal} = state, loot, group, eligible) do
    rollable =
      Enum.filter(loot.items, fn item ->
        not item.quest_item and not item.looted and item.quality >= group.loot_threshold
      end)

    {loot, rolls} =
      Enum.reduce(rollable, {loot, %{}}, fn item, {loot, rolls} ->
        roll = LootRoll.new(item.slot, item.item_id, item.count, eligible)
        {Loot.block_item(loot, item.slot), Map.put(rolls, item.slot, roll)}
      end)

    Enum.each(rolls, fn {slot, roll} ->
      packet = %Message.SmsgLootStartRoll{
        loot_guid: state.object.guid,
        slot: slot,
        item_id: roll.item_id,
        countdown: @loot_roll_countdown_ms
      }

      broadcast_roll_packet(roll, packet)
      Process.send_after(self(), {:loot_roll_timeout, slot}, @loot_roll_countdown_ms)
    end)

    internal = Map.put(%{internal | loot: loot}, :loot_rolls, rolls)
    %{state | internal: internal}
  end

  defp resolve_loot_roll(%Mob{internal: %Internal{} = internal} = state, slot) do
    case Map.pop(loot_rolls(internal), slot) do
      {%LootRoll{} = roll, rolls} ->
        state = %{state | internal: Map.put(internal, :loot_rolls, rolls)}

        state =
          case LootRoll.resolve(roll) do
            {:won, winner, number, vote, rolled} -> award_roll(state, roll, winner, number, vote, rolled)
            :all_passed -> pass_roll(state, roll)
          end

        maybe_finish_loot(state)

      {nil, _rolls} ->
        state
    end
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

    case EntityRegistry.whereis(winner) do
      pid when is_pid(pid) ->
        send(pid, {:create_item, roll.item_id, roll.count})
        take_rolled_item(state, roll.slot)

      _ ->
        unblock_slot(state, roll.slot)
    end
  end

  defp pass_roll(%Mob{} = state, roll) do
    broadcast_roll_packet(roll, %Message.SmsgLootAllPassed{
      loot_guid: state.object.guid,
      slot: roll.slot,
      item_id: roll.item_id
    })

    unblock_slot(state, roll.slot)
  end

  defp broadcast_roll_packet(roll, packet) do
    Enum.each(roll.eligible, &Network.send_packet(packet, &1))
  end

  defp take_rolled_item(%Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state, slot) do
    loot = Loot.unblock_item(loot, slot)

    loot =
      case Loot.take_item(loot, slot) do
        {:ok, _item, loot} -> loot
        _ -> loot
      end

    %{state | internal: %{internal | loot: loot}}
  end

  defp take_rolled_item(%Mob{} = state, _slot), do: state

  defp unblock_slot(%Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state, slot) do
    %{state | internal: %{internal | loot: Loot.unblock_item(loot, slot)}}
  end

  defp unblock_slot(%Mob{} = state, _slot), do: state

  defp maybe_finish_loot(%Mob{internal: %Internal{loot: %Loot{} = loot} = internal} = state) do
    if map_size(loot_rolls(internal)) == 0 and Loot.empty?(loot) do
      state = %{state | internal: %{internal | loot: nil}}
      state = clear_lootable_flag(state)
      Core.update_object(state, :values) |> World.broadcast_packet(state)
      state
    else
      state
    end
  end

  defp maybe_finish_loot(%Mob{} = state), do: state

  defp caster_guid(%{caster_guid: caster_guid}) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(caster_guid) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(_caster), do: nil

  defp schedule_respawn(%Mob{internal: %Internal{respawn_ref: ref}} = state) when is_reference(ref) do
    state
  end

  defp schedule_respawn(%Mob{internal: %Internal{} = internal} = state) do
    ref = Process.send_after(self(), :respawn, respawn_delay_ms(internal.respawn_delay_ms))
    %{state | internal: %{internal | respawn_ref: ref}}
  end

  defp clear_respawn_ref(%Mob{internal: %Internal{} = internal} = state) do
    %{state | internal: %{internal | respawn_ref: nil}}
  end

  defp respawn_delay_ms(delay) when is_integer(delay) and delay >= 0, do: delay
  defp respawn_delay_ms(_delay), do: @default_respawn_delay_ms

  defp update_metadata(%Mob{} = state) do
    Metadata.update(state.object.guid, %{
      bounding_radius: state.unit.bounding_radius,
      combat_reach: state.unit.combat_reach,
      level: state.unit.level,
      unit_flags: state.unit.flags,
      alive?: state.unit.health > 0
    })

    Metadata.update(state.object.guid, Mob.visibility_metadata(state))

    Metadata.update(state.object.guid, FactionLoader.metadata(state.unit.faction_template))
  end
end
