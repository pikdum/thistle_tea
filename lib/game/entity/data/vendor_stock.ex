defmodule ThistleTea.Game.Entity.Data.VendorStock do
  @moduledoc """
  A merchant's depleted stock and the interval selected on its last purchase.
  Full and unlimited inventory requires no stock record.
  """

  @enforce_keys [:count, :last_increment_at, :restock_ms]
  defstruct @enforce_keys

  defmodule Receipt do
    @moduledoc """
    A committed merchant purchase awaiting projection by the player owner.
    Stock, item rows, and this recovery receipt are written together.
    """

    @enforce_keys [:id, :guid, :changes, :old_counts, :vendor_guid, :vendor_item, :count, :available, :position]
    defstruct @enforce_keys
  end
end
