defmodule ThistleTea.Game.Entity.Logic.LootSession.Projection do
  @moduledoc false

  @enforce_keys [:loot, :tapped, :loot_method, :loot_master, :assigned_looter, :reserved_slots]
  defstruct [:loot, :tapped, :loot_method, :loot_master, :assigned_looter, :reserved_slots]
end

defmodule ThistleTea.Game.Entity.Logic.LootSession do
  @moduledoc """
  Pure loot policy and transaction state owned by a corpse or game object.

  Every decision is made from the same actor snapshot: tap and group rights,
  round-robin assignment, quest-item visibility, interaction distance, and
  master-loot recipient eligibility.
  """
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Logic.LootRoll
  alias ThistleTea.Game.Entity.Logic.LootSession.Projection

  @loot_method_round_robin 1
  @loot_method_master_loot 2
  @loot_slot_type_master 2
  @interaction_distance 5.0

  defstruct loot: %Loot{},
            rolls: %{},
            reservations: %{},
            tapped: nil,
            loot_method: nil,
            loot_master: nil,
            assigned_looter: nil,
            interaction_distance: @interaction_distance,
            viewers: MapSet.new()

  def new(%Loot{} = loot, tapped, opts \\ []) do
    %__MODULE__{
      loot: loot,
      tapped: normalize_tap(tapped),
      interaction_distance: Keyword.get(opts, :interaction_distance, @interaction_distance)
    }
  end

  def configure_group(%__MODULE__{} = session, loot_method) do
    %{session | loot_method: loot_method}
  end

  def view(%__MODULE__{} = session, %Actor{} = actor) do
    with :ok <- authorize_interaction(session, actor) do
      loot = visible_loot(session, actor)
      if Loot.empty?(loot), do: {:error, :nothing_to_take}, else: {:ok, loot}
    end
  end

  def visible?(%__MODULE__{} = session, %Actor{} = actor) do
    visible?(project(session), actor)
  end

  def visible?(%Projection{} = projection, %Actor{} = actor) do
    tap_allowed?(projection, actor) and not Loot.empty?(visible_loot(projection, actor))
  end

  def tap_allowed?(%{tapped: tapped} = policy, %Actor{} = actor) do
    method = Map.get(policy, :loot_method)
    assigned = Map.get(policy, :assigned_looter)

    tap_allowed?(tapped, actor) and
      (method != @loot_method_round_robin or assigned in [nil, actor.guid])
  end

  def tap_allowed?(nil, %Actor{}), do: true

  def tap_allowed?(%{group_id: group_id}, %Actor{group_id: group_id}) when is_integer(group_id), do: true

  def tap_allowed?(%{player: player, group_id: nil}, %Actor{guid: player}) when is_integer(player), do: true

  def tap_allowed?(%{player: player}, %Actor{guid: player}) when is_integer(player), do: true
  def tap_allowed?(_tapped, %Actor{}), do: false

  def reserve_item(%__MODULE__{} = session, %Actor{} = actor, slot, token) when is_reference(token) do
    with :ok <- authorize_interaction(session, actor),
         false <- reserved_slot?(session, slot),
         %Loot.Item{} = item <- available_item(session.loot, slot),
         true <- visible_item?(session, actor, item) do
      reserve(session, actor, item, token, false)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :already_looted}
    end
  end

  def take_gold(%__MODULE__{} = session, %Actor{} = actor) do
    with :ok <- authorize_interaction(session, actor),
         {:ok, gold, loot} <- Loot.take_gold(session.loot) do
      {:ok, gold, %{session | loot: loot}}
    end
  end

  def reserve_master(%__MODULE__{} = session, %Actor{} = giver, %Actor{} = recipient, slot, token)
      when is_reference(token) do
    with :ok <- authorize_interaction(session, giver),
         true <- session.loot_method == @loot_method_master_loot,
         true <- session.loot_master == giver.guid,
         true <- master_recipient?(session, recipient),
         %Loot.Item{} = item <- blocked_item(session, slot) do
      reserve(session, recipient, item, token, true)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :no_permission}
    end
  end

  def reserve_roll(%__MODULE__{} = session, %Actor{} = winner, slot, token) when is_reference(token) do
    with true <- tap_allowed?(session, winner),
         true <- Actor.within?(winner, Experience.group_reward_distance()),
         %Loot.Item{} = item <- blocked_item(session, slot) do
      reserve(session, winner, item, token, false)
    else
      _ -> {:error, :no_permission}
    end
  end

  def commit(%__MODULE__{} = session, %Commit{token: token, actor_guid: actor_guid}) do
    with %Reservation{actor_guid: ^actor_guid} = reservation <- Map.get(session.reservations, token),
         {:ok, item, loot} <- session.loot |> Loot.unblock_item(reservation.slot) |> Loot.commit_item(reservation.slot) do
      {:ok, item, %{session | loot: loot, reservations: Map.delete(session.reservations, token)}}
    else
      _ -> {:error, :invalid_reservation}
    end
  end

  def release(%__MODULE__{} = session, %Release{token: token, actor_guid: actor_guid}) do
    case Map.get(session.reservations, token) do
      %Reservation{actor_guid: ^actor_guid} -> {:ok, release_reservation(session, token)}
      _ -> {:error, :invalid_reservation}
    end
  end

  def release(%__MODULE__{} = session, token) when is_reference(token) do
    release_reservation(session, token)
  end

  def block_master_items(%__MODULE__{loot: %Loot{} = loot} = session, master, threshold) do
    loot =
      loot
      |> rollable_items(threshold)
      |> Enum.reduce(loot, fn item, loot -> Loot.block_item(loot, item.slot) end)

    %{session | loot: loot, loot_method: @loot_method_master_loot, loot_master: master}
  end

  def assign_looter(%__MODULE__{} = session, looter) do
    %{session | loot_method: @loot_method_round_robin, assigned_looter: looter}
  end

  def start_rolls(%__MODULE__{loot: %Loot{} = loot} = session, threshold, eligible) do
    rollable = rollable_items(loot, threshold)
    loot = Enum.reduce(rollable, loot, fn item, loot -> Loot.block_item(loot, item.slot) end)

    rolls =
      Map.new(rollable, fn item ->
        {item.slot, LootRoll.new(item.slot, item.item_id, item.count, eligible)}
      end)

    {%{session | loot: loot, rolls: rolls}, Map.values(rolls)}
  end

  def vote(%__MODULE__{} = session, slot, voter, vote) do
    with %LootRoll{} = roll <- Map.get(session.rolls, slot),
         {:ok, roll} <- LootRoll.vote(roll, voter, vote) do
      {:ok, %{session | rolls: Map.put(session.rolls, slot, roll)}, roll}
    else
      _ -> :error
    end
  end

  def pop_roll(%__MODULE__{} = session, slot) do
    {roll, rolls} = Map.pop(session.rolls, slot)
    {roll, %{session | rolls: rolls}}
  end

  def unblock_item(%__MODULE__{loot: %Loot{} = loot} = session, slot) do
    %{session | loot: Loot.unblock_item(loot, slot)}
  end

  def blocked_item(%__MODULE__{loot: %Loot{} = loot} = session, slot) do
    if !reserved_slot?(session, slot) do
      Enum.find(loot.items, fn item -> item.slot == slot and item.blocked and not item.looted end)
    end
  end

  def add_viewer(%__MODULE__{} = session, %Actor{guid: viewer}) do
    %{session | viewers: MapSet.put(session.viewers, viewer)}
  end

  def remove_viewer(%__MODULE__{} = session, %Actor{guid: viewer}) do
    %{session | viewers: MapSet.delete(session.viewers, viewer)}
  end

  def viewers(%__MODULE__{viewers: viewers}), do: MapSet.to_list(viewers)

  def pending?(%__MODULE__{rolls: rolls, reservations: reservations}) do
    map_size(rolls) > 0 or map_size(reservations) > 0
  end

  def finished?(%__MODULE__{loot: %Loot{} = loot} = session) do
    Loot.empty?(loot) and not pending?(session)
  end

  def project(%__MODULE__{} = session) do
    %Projection{
      loot: session.loot,
      tapped: session.tapped,
      loot_method: session.loot_method,
      loot_master: session.loot_master,
      assigned_looter: session.assigned_looter,
      reserved_slots: MapSet.new(session.reservations, fn {_token, reservation} -> reservation.slot end)
    }
  end

  defp authorize_interaction(%__MODULE__{} = session, %Actor{} = actor) do
    cond do
      not tap_allowed?(session, actor) -> {:error, :no_permission}
      not Actor.within?(actor, session.interaction_distance) -> {:error, :too_far}
      true -> :ok
    end
  end

  defp master_recipient?(%__MODULE__{} = session, %Actor{} = recipient) do
    tap_allowed?(session.tapped, recipient) and Actor.within?(recipient, Experience.group_reward_distance())
  end

  defp visible_loot(%{loot: %Loot{} = loot} = policy, %Actor{} = actor) do
    reserved_slots = policy_reserved_slots(policy)

    items =
      loot.items
      |> Enum.reject(&MapSet.member?(reserved_slots, &1.slot))
      |> Enum.filter(&visible_item?(policy, actor, &1))
      |> Enum.map(fn item ->
        if item.blocked, do: %{item | slot_type: @loot_slot_type_master}, else: item
      end)

    %{loot | items: items}
  end

  defp visible_item?(policy, %Actor{} = actor, %Loot.Item{} = item) do
    not item.looted and
      (not item.quest_item or Actor.needs_item?(actor, item.item_id)) and
      (not item.blocked or actor.guid == Map.get(policy, :loot_master))
  end

  defp available_item(%Loot{items: items}, slot) do
    Enum.find(items, fn item -> item.slot == slot and not item.looted and not item.blocked end)
  end

  defp reserve(%__MODULE__{} = session, %Actor{} = actor, %Loot.Item{} = item, token, release_blocked?) do
    reservation = %Reservation{
      token: token,
      slot: item.slot,
      actor_guid: actor.guid,
      item: item,
      release_blocked?: release_blocked?
    }

    {:ok, reservation, %{session | reservations: Map.put(session.reservations, token, reservation)}}
  end

  defp reserved_slot?(%__MODULE__{} = session, slot) do
    Enum.any?(session.reservations, fn {_token, %Reservation{slot: reserved}} -> reserved == slot end)
  end

  defp reserved_slots(%__MODULE__{} = session) do
    MapSet.new(session.reservations, fn {_token, reservation} -> reservation.slot end)
  end

  defp policy_reserved_slots(%Projection{reserved_slots: reserved_slots}), do: reserved_slots
  defp policy_reserved_slots(%__MODULE__{} = session), do: reserved_slots(session)

  defp release_reservation(%__MODULE__{} = session, token) do
    case Map.pop(session.reservations, token) do
      {%Reservation{release_blocked?: true}, reservations} ->
        %{session | reservations: reservations}

      {%Reservation{slot: slot}, reservations} ->
        %{session | loot: Loot.unblock_item(session.loot, slot), reservations: reservations}

      {nil, _reservations} ->
        session
    end
  end

  defp rollable_items(%Loot{items: items}, threshold) do
    Enum.filter(items, fn item ->
      not item.quest_item and not item.looted and not item.blocked and item.quality >= threshold
    end)
  end

  defp normalize_tap(player) when is_integer(player), do: %{player: player, group_id: nil}
  defp normalize_tap(tapped), do: tapped
end
