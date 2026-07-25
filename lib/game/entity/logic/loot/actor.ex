defmodule ThistleTea.Game.Entity.Logic.Loot.Actor do
  @moduledoc false

  @enforce_keys [:guid, :group_id, :needed_items, :distance]
  defstruct [:guid, :group_id, :needed_items, :distance]

  @type t :: %__MODULE__{
          guid: integer(),
          group_id: integer() | nil,
          needed_items: MapSet.t(integer()) | :unknown,
          distance: number() | nil
        }

  def needs_item?(%__MODULE__{needed_items: %MapSet{} = needed_items}, item_id) do
    MapSet.member?(needed_items, item_id)
  end

  def needs_item?(%__MODULE__{needed_items: :unknown}, _item_id), do: true

  def within?(%__MODULE__{distance: distance}, maximum) when is_number(distance) and is_number(maximum) do
    distance <= maximum
  end

  def within?(%__MODULE__{}, _maximum), do: false
end
