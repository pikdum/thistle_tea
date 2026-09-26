defmodule ThistleTea.Game.Terrain.Liquid do
  @moduledoc "A sampled terrain liquid column, including its surface, floor, and client liquid flags."

  import Bitwise, only: [&&&: 2]

  @enforce_keys [:flags, :surface, :floor]
  defstruct [:flags, :surface, :floor, :entry]

  def from_wmo({entry, surface, floor}) when entry in [1, 2, 3, 4, 21] do
    flags = %{1 => 8, 2 => 2, 3 => 1, 4 => 4, 21 => 4}
    %__MODULE__{entry: entry, flags: Map.fetch!(flags, entry), surface: surface, floor: floor}
  end

  def from_wmo(_liquid), do: nil

  def high_sea?(%__MODULE__{flags: flags}), do: (flags &&& 0x10) != 0
  def high_sea?(_liquid), do: false

  def magma?(%__MODULE__{flags: flags}), do: (flags &&& 0x01) != 0
  def magma?(_liquid), do: false

  def touching?(%__MODULE__{surface: surface}, z), do: trunc((surface - z - 0.01) * 10) > -1

  def spell_id(%__MODULE__{entry: 21, surface: surface}, z) do
    if trunc((surface - z - 0.01) * 10) > 0, do: 28_801
  end

  def spell_id(_liquid, _z), do: nil
end
