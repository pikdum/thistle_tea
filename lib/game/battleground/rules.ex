defmodule ThistleTea.Game.Battleground.Rules do
  @moduledoc "Selects the pure rules for supported battleground maps."

  alias ThistleTea.Game.Battleground.ArathiBasin
  alias ThistleTea.Game.Battleground.WarsongGulch

  def for_map(489), do: WarsongGulch
  def for_map(529), do: ArathiBasin
  def for_map(_map_id), do: nil

  def fetch!(map_id) do
    case for_map(map_id) do
      nil -> raise ArgumentError, "unsupported battleground map: #{map_id}"
      rules -> rules
    end
  end

  def initial_events(489), do: %{0 => 0, 1 => 0, 2 => 0, 253 => 0, 254 => 0}
  def initial_events(529), do: %{0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 0, 253 => 0, 254 => 0}
  def initial_events(_map_id), do: %{}
end
