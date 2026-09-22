defmodule ThistleTea.Game.Entity.Data.CombatLeash do
  @moduledoc """
  One engagement's origin and locally observed leash extensions. References
  distinguish both creature incarnations and successive fights by one owner.
  """

  defstruct [:origin, :last_extended_at, :next_control_at, generation: 0, active?: false]

  defmodule Ref do
    @moduledoc false
    @enforce_keys [:world, :guid, :incarnation, :generation]
    defstruct [:world, :guid, :incarnation, :generation]
  end

  defmodule Owner do
    @moduledoc false
    @enforce_keys [:world, :guid, :incarnation, :pid]
    defstruct [:world, :guid, :incarnation, :pid]
  end
end
