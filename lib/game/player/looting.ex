defmodule ThistleTea.Game.Player.Looting do
  @moduledoc """
  Player-owned loot orchestration: builds actor snapshots, opens and closes
  sessions, transfers reserved items, and projects the resulting packets.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.ItemLoot, as: PendingItemLoot
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.Pickpocket
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Containers
  alias ThistleTea.Game.Player.ItemLoot
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  require Logger

  @loot_method_master_loot 2

  def actor(%{character: %Character{} = character}, loot_guid) do
    ActorFactory.for_character(character, loot_guid)
  end

  def remote_actor(guid, loot_guid), do: ActorFactory.for_guid(guid, loot_guid)

  def pickpocket(%{character: %Character{} = character} = state, guid, spell_id) do
    metadata = Metadata.get(guid) || %{}

    target =
      metadata
      |> Map.put(:guid, guid)
      |> Map.put(:friendly?, Hostility.friendly?(character, Map.put(metadata, :guid, guid)))

    with false <- Core.dead?(character) or ControlMovement.active?(character),
         :ok <- Pickpocket.validate_target(character, target) do
      state = release(state)

      case Entity.call(guid, {:pickpocket, actor(state, guid), character.unit.level}) do
        {:ok, %Loot{} = loot} ->
          Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: loot, loot_type: 2})
          %{state | loot_guid: guid, loot_type: :pickpocket}

        _ ->
          Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
          state
      end
    else
      {:error, reason} ->
        Network.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
        state

      _ ->
        state
    end
  end

  def open(state, guid, opts \\ [])

  def open(%{character: %Character{} = character} = state, guid, opts) do
    if ControlMovement.active?(character) do
      Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
      release(state)
    else
      open_available(state, guid, opts)
    end
  end

  def open(state, guid, _opts) do
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end

  defp open_available(
         %{character: %Character{internal: %{item_loot: %PendingItemLoot{guid: guid}}}} = state,
         guid,
         _opts
       ) do
    state |> release() |> ItemLoot.open()
  end

  defp open_available(%{character: %Character{} = character} = state, guid, opts) do
    if Guid.entity_type(guid) == :item do
      Containers.open_guid(state, guid)
    else
      open_entity(state, character, guid, opts)
    end
  end

  defp open_entity(state, character, guid, opts) do
    state = release(state)
    actor = actor(state, guid)
    command = if Keyword.get(opts, :insignia?, false), do: :insignia_view, else: :loot_view

    with false <- Core.dead?(character),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {command, actor}) do
      if Guid.entity_type(guid) == :game_object do
        InstanceSystem.game_object_used(character.internal.world, Guid.entry(guid))
      end

      skinned? = match?(%{skinned?: true}, Metadata.query(guid, [:skinned?]))

      Network.send_packet(%Message.SmsgLootResponse{
        guid: guid,
        loot: loot,
        loot_type: if(skinned?, do: 2, else: Keyword.get(opts, :loot_type, 1))
      })

      if !skinned?, do: maybe_send_master_list(state, guid)
      %{state | loot_guid: guid, loot_type: if(skinned?, do: :skinning, else: :corpse)}
    else
      {:error, :nothing_to_take} ->
        Entity.call(guid, {:loot_release, actor})
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state

      {:error, :no_permission} ->
        Network.send_packet(%Message.SmsgLootResponse{guid: guid, loot: %Loot{}})
        state

      _ ->
        Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
        state
    end
  end

  def release(%{loot_type: :container} = state) do
    state = Containers.release(state)
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.loot_guid})
    %{state | loot_guid: nil, loot_type: nil}
  end

  def release(%{loot_type: :item} = state) do
    state = ItemLoot.release(state)
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.loot_guid})
    %{state | loot_guid: nil, loot_type: nil}
  end

  def release(%{character: %Character{}} = state) when is_integer(state.loot_guid) do
    actor = actor(state, state.loot_guid)
    loot_call(state, actor, :release)
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.loot_guid})
    %{state | loot_guid: nil, loot_type: nil}
  end

  def release(state), do: state

  def close_unavailable(%{character: %Character{} = character, loot_guid: guid} = state) when is_integer(guid) do
    if Core.dead?(character) or ControlMovement.active?(character) or chest_out_of_range?(character, guid) or
         container_unavailable?(state),
       do: release(state),
       else: state
  end

  def close_unavailable(state), do: state

  defp container_unavailable?(%{loot_type: :container, loot_guid: guid} = state),
    do: not Containers.available?(state, guid)

  defp container_unavailable?(_state), do: false

  defp chest_out_of_range?(character, guid) do
    if Guid.entity_type(guid) == :game_object and
         match?(%{type: 3}, GameObjectTemplateLoader.cached(Guid.entry(guid))) do
      case World.distance_between(character, guid) do
        distance when is_number(distance) and distance <= 5.0 -> false
        _ -> true
      end
    else
      false
    end
  end

  def take_item(%{loot_type: :item} = state, slot), do: ItemLoot.take_item(state, slot)
  def take_item(%{loot_type: :container} = state, slot), do: Containers.take_item(state, slot)

  def take_item(%{character: %Character{}, loot_guid: loot_guid} = state, slot) when is_integer(loot_guid) do
    actor = actor(state, loot_guid)

    case loot_call(state, actor, {:reserve_item, slot}) do
      {:ok, %Reservation{} = reservation} -> accept_reservation(state, loot_guid, reservation)
      _ -> inventory_failure(state, :already_looted)
    end
  end

  def take_item(state, _slot), do: state

  def accept_reservation(%{character: %Character{}} = state, loot_guid, %Reservation{} = reservation) do
    actor = actor(state, loot_guid)

    with :ok <- Entity.call(loot_guid, {:loot_validate_commit, actor, reservation.token}),
         {:ok, state, placed_at} <- Items.store(state, reservation.item.item_id, reservation.item.count) do
      commit = %Commit{token: reservation.token, actor_guid: state.guid}
      Entity.loot_reservation_result(loot_guid, commit)
      Items.send_push_result(state, reservation.item.item_id, reservation.item.count, placed_at)
      state
    else
      {:error, reason, state} ->
        release_reservation(loot_guid, reservation)
        inventory_failure(state, reason)

      {:error, reason} ->
        release_reservation(loot_guid, reservation)
        inventory_failure(state, reason)
    end
  rescue
    error ->
      release_reservation(loot_guid, reservation)
      Logger.error("loot transfer crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      inventory_failure(state, :inventory_full)
  end

  def accept_reservation(state, loot_guid, %Reservation{} = reservation) do
    release_reservation(loot_guid, reservation)
    inventory_failure(state, :inventory_full)
  end

  def take_money(%{loot_type: :item} = state), do: state
  def take_money(%{loot_type: :container} = state), do: Containers.take_money(state)

  def take_money(%{character: %Character{} = character, loot_guid: loot_guid} = state) when is_integer(loot_guid) do
    actor = actor(state, loot_guid)

    case loot_call(state, actor, :take_gold) do
      {:ok, gold} ->
        share = if Map.get(state, :loot_type) == :pickpocket, do: gold, else: split_gold(state.guid, character, gold)
        player = %{character.player | coinage: character.player.coinage + share}
        Network.send_packet(%Message.SmsgLootMoneyNotify{money: share})
        Network.send_packet(%Message.SmsgLootClearMoney{})
        InventoryUpdate.apply(state, {:ok, player})

      _ ->
        state
    end
  end

  def take_money(state), do: state

  def master_give(%{loot_guid: loot_guid} = state, loot_guid, slot, target) do
    giver = actor(state, loot_guid)
    recipient = remote_actor(target, loot_guid)
    Entity.call(loot_guid, {:loot_master_give, giver, slot, recipient})
    state
  end

  def master_give(state, _loot_guid, _slot, _target), do: state

  defp loot_call(%{loot_guid: guid, loot_type: :pickpocket}, actor, command) do
    Entity.call(guid, {:pocket_loot, actor, command})
  end

  defp loot_call(%{loot_guid: guid}, actor, {:reserve_item, slot}) do
    Entity.call(guid, {:loot_reserve_item, actor, slot})
  end

  defp loot_call(%{loot_guid: guid}, actor, :take_gold), do: Entity.call(guid, {:loot_take_gold, actor})
  defp loot_call(%{loot_guid: guid}, actor, :release), do: Entity.call(guid, {:loot_release, actor})

  defp release_reservation(loot_guid, %Reservation{} = reservation) do
    release = %Release{token: reservation.token, actor_guid: reservation.actor_guid}
    Entity.loot_reservation_result(loot_guid, release)
  end

  defp inventory_failure(state, reason) do
    reason = if reason in [:item_not_found, :inventory_full], do: reason, else: :already_looted
    InventoryUpdate.send_failure(reason, 0, 0)
    state
  end

  defp split_gold(guid, character, gold) do
    case PartySystem.group_of(guid) do
      %Party.Group{} = group ->
        others = nearby_members(guid, character, group)
        share = div(gold, length(others) + 1)
        Enum.each(others, &Entity.receive_money(&1, share))
        share

      _ ->
        gold
    end
  end

  defp nearby_members(guid, character, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    character
    |> World.nearby_players(Experience.group_reward_distance())
    |> Enum.map(fn {other_guid, _distance} -> other_guid end)
    |> Enum.filter(fn other_guid -> other_guid != guid and MapSet.member?(member_guids, other_guid) end)
  end

  defp maybe_send_master_list(%{guid: viewer}, corpse_guid) do
    with %Party.Group{loot_method: @loot_method_master_loot, master_looter: ^viewer} = group <-
           PartySystem.group_of(viewer),
         {world, x, y, z} <- World.position(corpse_guid) do
      member_guids = MapSet.new(group.members, & &1.guid)

      looters =
        World.nearby_players_at(world, {x, y, z}, Experience.group_reward_distance())
        |> Enum.map(fn {guid, _distance} -> guid end)
        |> Enum.filter(&MapSet.member?(member_guids, &1))

      packet = %Message.SmsgLootMasterList{looters: looters}
      Enum.each(looters, &Network.send_packet(packet, &1))
    else
      _ -> :ok
    end
  end
end
