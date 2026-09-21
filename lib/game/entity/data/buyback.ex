defmodule ThistleTea.Game.Entity.Data.Buyback do
  @moduledoc """
  Session-local vendor buyback entries. Items remain in ItemStore; the entries
  own their sale price, slot order, and time spent outside carried inventory.
  """

  defmodule Entry do
    @moduledoc false
    @enforce_keys [:guid, :price, :sold_at, :timestamp]
    defstruct @enforce_keys
  end

  defmodule Change do
    @moduledoc false
    @enforce_keys [:inventory, :buyback]
    defstruct @enforce_keys ++ [sold_guid: nil, removed_from_inventory?: false]
  end

  defstruct entries: %{}, next_slot: 69, started_at: nil
end
