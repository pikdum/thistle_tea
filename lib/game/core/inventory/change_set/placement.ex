defmodule ThistleTea.Game.Core.Inventory.ChangeSet.Placement do
  @moduledoc false

  @enforce_keys [:incoming_guid, :status]
  defstruct [:incoming_guid, :status, :position, :item]
end
