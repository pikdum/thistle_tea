defmodule ThistleTea.Game.Core.Battleground.Rules do
  @moduledoc "Selects the pure rules for supported battleground maps."

  alias ThistleTea.Game.Core.Battleground.AlteracValley
  alias ThistleTea.Game.Core.Battleground.ArathiBasin
  alias ThistleTea.Game.Core.Battleground.Result
  alias ThistleTea.Game.Core.Battleground.WarsongGulch

  def for_map(30), do: AlteracValley
  def for_map(489), do: WarsongGulch
  def for_map(529), do: ArathiBasin
  def for_map(_map_id), do: nil

  def fetch!(map_id) do
    case for_map(map_id) do
      nil -> raise ArgumentError, "unsupported battleground map: #{map_id}"
      rules -> rules
    end
  end

  def initial_events(30), do: AlteracValley.initial_events()
  def initial_events(489), do: %{0 => 0, 1 => 0, 2 => 0, 253 => 0, 254 => 0}
  def initial_events(529), do: %{0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 0, 253 => 0, 254 => 0}
  def initial_events(_map_id), do: %{}

  def weekend_event(30), do: 18
  def weekend_event(489), do: 19
  def weekend_event(529), do: 20

  def creature_event(%AlteracValley{} = match, entry, event), do: AlteracValley.creature_event(match, entry, event)
  def creature_event(match, _entry, _event), do: %Result{match: match}
end
