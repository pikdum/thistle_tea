defmodule ThistleTea.Game.Entity.Logic.LootSession do
  @moduledoc """
  Pure corpse-loot state: the rolled loot, pending need/greed rolls, the tap
  snapshot, and master/assigned looter, with the permission and per-viewer
  view rules. The owning boundary handles timers and packets.
  """
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.LootRoll

  @loot_method_round_robin 1
  @loot_slot_type_master 2

  defstruct loot: %Loot{}, rolls: %{}, tapped: nil, loot_master: nil, assigned_looter: nil, viewers: MapSet.new()

  def new(%Loot{} = loot, tapped) do
    %__MODULE__{loot: loot, tapped: tapped}
  end

  def allowed?(%__MODULE__{tapped: nil}, _viewer, _viewer_group), do: true

  def allowed?(%__MODULE__{tapped: %{group_id: group_id}} = session, viewer, viewer_group) when is_integer(group_id) do
    case viewer_group do
      %{id: ^group_id, loot_method: @loot_method_round_robin} -> session.assigned_looter in [nil, viewer]
      %{id: ^group_id} -> true
      _ -> false
    end
  end

  def allowed?(%__MODULE__{tapped: %{player: player}}, viewer, _viewer_group), do: player == viewer

  def view(%__MODULE__{loot: %Loot{} = loot} = session, viewer) do
    items =
      loot.items
      |> Enum.reject(fn item -> item.blocked and viewer != session.loot_master end)
      |> Enum.map(fn item ->
        if item.blocked, do: %{item | slot_type: @loot_slot_type_master}, else: item
      end)

    %{loot | items: items}
  end

  def block_master_items(%__MODULE__{loot: %Loot{} = loot} = session, master, threshold) do
    loot =
      loot
      |> rollable_items(threshold)
      |> Enum.reduce(loot, fn item, loot -> Loot.block_item(loot, item.slot) end)

    %{session | loot: loot, loot_master: master}
  end

  def assign_looter(%__MODULE__{} = session, looter) do
    %{session | assigned_looter: looter}
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

  def take_item(%__MODULE__{loot: %Loot{} = loot} = session, slot) do
    case Loot.take_item(loot, slot) do
      {:ok, item, loot} -> {:ok, item, %{session | loot: loot}}
      error -> error
    end
  end

  def return_item(%__MODULE__{loot: %Loot{} = loot} = session, slot) do
    %{session | loot: Loot.return_item(loot, slot)}
  end

  def take_gold(%__MODULE__{loot: %Loot{} = loot} = session) do
    case Loot.take_gold(loot) do
      {:ok, gold, loot} -> {:ok, gold, %{session | loot: loot}}
      error -> error
    end
  end

  def award_item(%__MODULE__{} = session, slot) do
    session
    |> unblock_item(slot)
    |> take_item(slot)
  end

  def unblock_item(%__MODULE__{loot: %Loot{} = loot} = session, slot) do
    %{session | loot: Loot.unblock_item(loot, slot)}
  end

  def blocked_item(%__MODULE__{loot: %Loot{} = loot}, slot) do
    Enum.find(loot.items, fn item -> item.slot == slot and item.blocked and not item.looted end)
  end

  def add_viewer(%__MODULE__{} = session, viewer) do
    %{session | viewers: MapSet.put(session.viewers, viewer)}
  end

  def remove_viewer(%__MODULE__{} = session, viewer) do
    %{session | viewers: MapSet.delete(session.viewers, viewer)}
  end

  def viewers(%__MODULE__{viewers: viewers}), do: MapSet.to_list(viewers)

  def rolls_pending?(%__MODULE__{rolls: rolls}), do: map_size(rolls) > 0

  def finished?(%__MODULE__{loot: %Loot{} = loot} = session) do
    Loot.empty?(loot) and not rolls_pending?(session)
  end

  defp rollable_items(%Loot{items: items}, threshold) do
    Enum.filter(items, fn item ->
      not item.quest_item and not item.looted and not item.blocked and item.quality >= threshold
    end)
  end
end
