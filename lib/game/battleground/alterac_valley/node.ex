defmodule ThistleTea.Game.Battleground.AlteracValley.Node do
  @moduledoc "Alterac graveyard ownership, permanent tower destruction, and event and map projections."

  alias ThistleTea.Game.Battleground.ControlPoint

  @enforce_keys [:id, :name, :kind, :home_team, :point]
  defstruct [:id, :name, :kind, :home_team, :point, destroyed?: false]

  @capture_ms 300_000
  @definitions [
    {"Stormpike Aid Station", :graveyard, :alliance, [1_326, 1_325, 1_328, 1_327]},
    {"Stormpike Graveyard", :graveyard, :alliance, [1_335, 1_333, 1_336, 1_334]},
    {"Stonehearth Graveyard", :graveyard, :alliance, [1_304, 1_302, 1_303, 1_301]},
    {"Snowfall Graveyard", :graveyard, nil, [1_343, 1_341, 1_344, 1_342]},
    {"Iceblood Graveyard", :graveyard, :horde, [1_348, 1_346, 1_349, 1_347]},
    {"Frostwolf Graveyard", :graveyard, :horde, [1_339, 1_337, 1_340, 1_338]},
    {"Frostwolf Relief Hut", :graveyard, :horde, [1_331, 1_329, 1_332, 1_330]},
    {"Dun Baldar South Bunker", :tower, :alliance, [1_375, 1_361, 1_378, 1_370]},
    {"Dun Baldar North Bunker", :tower, :alliance, [1_374, 1_362, 1_379, 1_371]},
    {"Icewing Bunker", :tower, :alliance, [1_376, 1_363, 1_380, 1_372]},
    {"Stonehearth Bunker", :tower, :alliance, [1_377, 1_364, 1_381, 1_373]},
    {"Iceblood Tower", :tower, :horde, [1_390, 1_368, 1_395, 1_385]},
    {"Tower Point", :tower, :horde, [1_389, 1_367, 1_394, 1_384]},
    {"East Frostwolf Tower", :tower, :horde, [1_388, 1_366, 1_393, 1_383]},
    {"West Frostwolf Tower", :tower, :horde, [1_387, 1_365, 1_392, 1_382]}
  ]

  def all, do: Map.new(0..14, &{&1, new(&1)})
  def capture_ms, do: @capture_ms

  def new(id) when id in 0..14 do
    {name, kind, team, _fields} = Enum.at(@definitions, id)
    %__MODULE__{id: id, name: name, kind: kind, home_team: team, point: %ControlPoint{owner: team}}
  end

  def assault(%__MODULE__{destroyed?: true} = node, _team, _now), do: {:unchanged, node}

  def assault(%__MODULE__{} = node, team, now) do
    {action, point} = ControlPoint.assault(node.point, team, now, @capture_ms)
    {action, %{node | point: point}}
  end

  def capture(%__MODULE__{} = node, revision, now) do
    case ControlPoint.capture(node.point, revision, now) do
      {:captured, point} -> {:captured, %{node | point: point, destroyed?: node.kind == :tower}}
      {:unchanged, _point} -> {:unchanged, node}
    end
  end

  def controlled_by(%__MODULE__{destroyed?: true}), do: nil
  def controlled_by(%__MODULE__{point: point}), do: ControlPoint.controlled_by(point)

  def event_state(%__MODULE__{point: %ControlPoint{assaulting: :alliance}}), do: 0
  def event_state(%__MODULE__{point: %ControlPoint{assaulting: :horde}}), do: 2
  def event_state(%__MODULE__{point: %ControlPoint{owner: :alliance}}), do: 1
  def event_state(%__MODULE__{point: %ControlPoint{owner: :horde}}), do: 3
  def event_state(%__MODULE__{}), do: 5

  def defender_events(node, upgrade \\ 0)

  def defender_events(%__MODULE__{id: id, kind: :graveyard, point: %ControlPoint{owner: nil}}, _upgrade),
    do: [{15 + id, 8}]

  def defender_events(%__MODULE__{id: id, kind: :graveyard, point: point}, upgrade) when upgrade in 0..3 do
    [{15 + id, team_index(point.owner) * 4 + upgrade}]
  end

  def defender_events(%__MODULE__{id: id, kind: :tower, point: point}, upgrade) when upgrade in 0..3 do
    [{15 + id, team_index(point.owner) * 2 + 1}, {23 + id, team_index(point.owner) * 4 + upgrade}]
  end

  def world_states(%__MODULE__{id: id} = node) do
    {_name, _kind, _team, fields} = Enum.at(@definitions, id)
    state = event_state(node)
    states = Enum.zip_with(fields, [1, 0, 3, 2], &{&1, if(&2 == state, do: 1, else: 0)})
    if id == 3, do: [{1_966, if(state == 5, do: 1, else: 0)} | states], else: states
  end

  defp team_index(:alliance), do: 0
  defp team_index(:horde), do: 1
  defp team_index(nil), do: 2
end
