defmodule ThistleTea.Game.Terrain.Liquid do
  @moduledoc "A sampled terrain liquid column, including its surface, floor, and client liquid flags."

  import Bitwise, only: [&&&: 2]

  @enforce_keys [:flags, :surface, :floor]
  defstruct [:flags, :surface, :floor]

  def high_sea?(%__MODULE__{flags: flags}), do: (flags &&& 0x10) != 0
  def high_sea?(_liquid), do: false
end
