defmodule ThistleTea.Game.Entity.Logic.Inventory.ChangeSet do
  @moduledoc """
  The complete result of a planned inventory transaction.

  Existing item updates, removals, and new placements remain data until the
  player boundary commits the change set in one projection step.
  """

  alias __MODULE__.Placement
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item

  @enforce_keys [:player]
  defstruct [:player, changed: %{}, destroyed: %{}, placements: []]

  def new(%Player{} = player), do: %__MODULE__{player: player}

  def put_player(%__MODULE__{} = change_set, %Player{} = player) do
    %{change_set | player: player}
  end

  def absorb(%__MODULE__{} = change_set, %{player: %Player{} = player, items: items, destroyed: destroyed})
      when is_list(items) and is_list(destroyed) do
    change_set = %{change_set | player: player}
    change_set = Enum.reduce(items, change_set, &put_changed(&2, &1))
    Enum.reduce(destroyed, change_set, &put_destroyed(&2, &1))
  end

  def place(%__MODULE__{} = change_set, %Item{object: %{guid: guid}}, :merged) do
    placement = %Placement{incoming_guid: guid, status: :merged}
    %{change_set | placements: change_set.placements ++ [placement]}
  end

  def place(%__MODULE__{} = change_set, %Item{object: %{guid: guid}}, {:placed, position, %Item{} = placed}) do
    placement = %Placement{incoming_guid: guid, status: :placed, position: position, item: placed}
    %{change_set | placements: change_set.placements ++ [placement]}
  end

  def get_item(%__MODULE__{} = change_set, guid, fallback) when is_integer(guid) and is_function(fallback, 1) do
    cond do
      Map.has_key?(change_set.destroyed, guid) -> nil
      Map.has_key?(change_set.changed, guid) -> Map.fetch!(change_set.changed, guid)
      item = placed_item(change_set, guid) -> item
      true -> fallback.(guid)
    end
  end

  def changed_items(%__MODULE__{changed: changed}), do: sorted_items(changed)
  def destroyed_items(%__MODULE__{destroyed: destroyed}), do: sorted_items(destroyed)

  def placed_items(%__MODULE__{placements: placements}) do
    Enum.flat_map(placements, fn
      %Placement{status: :placed, item: %Item{} = item} -> [item]
      %Placement{} -> []
    end)
  end

  def placement(%__MODULE__{placements: placements}, incoming_guid) when is_integer(incoming_guid) do
    Enum.find(placements, &(&1.incoming_guid == incoming_guid))
  end

  defp put_changed(%__MODULE__{} = change_set, %Item{object: %{guid: guid}} = item) do
    {placements, placed?} =
      Enum.map_reduce(change_set.placements, false, fn
        %Placement{status: :placed, item: %Item{object: %{guid: ^guid}}} = placement, _placed? ->
          {%{placement | item: item}, true}

        placement, placed? ->
          {placement, placed?}
      end)

    if placed? do
      %{change_set | placements: placements}
    else
      %{change_set | changed: Map.put(change_set.changed, guid, item)}
    end
  end

  defp put_destroyed(%__MODULE__{} = change_set, %Item{object: %{guid: guid}} = item) do
    %{
      change_set
      | changed: Map.delete(change_set.changed, guid),
        destroyed: Map.put(change_set.destroyed, guid, item)
    }
  end

  defp placed_item(%__MODULE__{placements: placements}, guid) do
    Enum.find_value(placements, fn
      %Placement{status: :placed, item: %Item{object: %{guid: ^guid}} = item} -> item
      %Placement{} -> nil
    end)
  end

  defp sorted_items(items), do: items |> Map.values() |> Enum.sort_by(& &1.object.guid)
end
