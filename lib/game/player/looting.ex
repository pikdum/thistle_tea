defmodule ThistleTea.Game.Player.Looting do
  @moduledoc """
  Player-owned loot orchestration: builds actor snapshots, opens and closes
  sessions, transfers reserved items, and projects the resulting packets.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Loot.ActorFactory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  require Logger

  @loot_method_master_loot 2

  def actor(%{character: %Character{} = character}, loot_guid) do
    ActorFactory.for_character(character, loot_guid)
  end

  def remote_actor(guid, loot_guid), do: ActorFactory.for_guid(guid, loot_guid)

  def open(state, guid, opts \\ [])

  def open(%{character: %Character{} = character} = state, guid, opts) do
    actor = actor(state, guid)

    with false <- Core.dead?(character),
         {:ok, %Loot{} = loot} <- Entity.call(guid, {:loot_view, actor}) do
      Network.send_packet(%Message.SmsgLootResponse{
        guid: guid,
        loot: loot,
        loot_type: Keyword.get(opts, :loot_type, 1)
      })

      maybe_send_master_list(state, guid)
      %{state | loot_guid: guid}
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

  def open(state, guid, _opts) do
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: guid})
    state
  end

  def release(%{character: %Character{}} = state) when is_integer(state.loot_guid) do
    actor = actor(state, state.loot_guid)
    Entity.call(state.loot_guid, {:loot_release, actor})
    Network.send_packet(%Message.SmsgLootReleaseResponse{guid: state.loot_guid})
    %{state | loot_guid: nil}
  end

  def release(state), do: state

  def take_item(%{character: %Character{}, loot_guid: loot_guid} = state, slot) when is_integer(loot_guid) do
    actor = actor(state, loot_guid)

    case Entity.call(loot_guid, {:loot_reserve_item, actor, slot}) do
      {:ok, %Reservation{} = reservation} -> accept_reservation(state, loot_guid, reservation)
      _ -> inventory_failure(state, :already_looted)
    end
  end

  def take_item(state, _slot), do: state

  def accept_reservation(state, loot_guid, %Reservation{} = reservation) do
    case Items.store(state, reservation.item.item_id, reservation.item.count) do
      {:ok, state, placed_at} ->
        commit = %Commit{token: reservation.token, actor_guid: state.guid}
        Entity.loot_reservation_result(loot_guid, commit)
        Items.send_push_result(state, reservation.item.item_id, reservation.item.count, placed_at)
        state

      {:error, reason, state} ->
        release_reservation(loot_guid, reservation)
        inventory_failure(state, reason)
    end
  rescue
    error ->
      release_reservation(loot_guid, reservation)
      Logger.error("loot transfer crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      inventory_failure(state, :inventory_full)
  end

  def take_money(%{character: %Character{} = character, loot_guid: loot_guid} = state) when is_integer(loot_guid) do
    actor = actor(state, loot_guid)

    case Entity.call(loot_guid, {:loot_take_gold, actor}) do
      {:ok, gold} ->
        share = split_gold(state.guid, character, gold)
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
         {^corpse_guid, map, x, y, z} <- SpatialHash.get_entity(corpse_guid) do
      member_guids = MapSet.new(group.members, & &1.guid)

      looters =
        SpatialHash.query(:players, map, x, y, z, Experience.group_reward_distance())
        |> Enum.map(fn {guid, _distance} -> guid end)
        |> Enum.filter(&MapSet.member?(member_guids, &1))

      packet = %Message.SmsgLootMasterList{looters: looters}
      Enum.each(looters, &Network.send_packet(packet, &1))
    else
      _ -> :ok
    end
  end
end
