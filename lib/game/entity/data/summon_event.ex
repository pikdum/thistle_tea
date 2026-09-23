defmodule ThistleTea.Game.Entity.Data.SummonEvent do
  @moduledoc "A summon lifecycle edge with its final observation retained across process cleanup."

  @enforce_keys [:event, :entry, :world, :observation]
  defstruct [:event, :entry, :world, :observation]
end
