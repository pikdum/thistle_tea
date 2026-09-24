defmodule ThistleTea.Game.OutdoorPvp.Towers do
  @moduledoc "Pure regional capture-point ownership, membership, and client projections."

  alias ThistleTea.Game.Math
  alias ThistleTea.Game.OutdoorPvp.CapturePoint
  alias ThistleTea.Game.OutdoorPvp.CapturePoint.Template
  alias ThistleTea.Game.OutdoorPvp.Plaguelands
  alias ThistleTea.Game.WorldRef

  defstruct points: %{}, members: %{}

  defmodule Participant do
    @moduledoc false
    defstruct [:guid, :team, :world, :position, eligible?: false]
  end

  def new(templates) when is_map(templates) do
    points =
      for {id, definition} <- Plaguelands.towers(),
          %Template{} = template <- [Map.get(templates, definition.entry)],
          into: %{},
          do: {id, CapturePoint.new(template)}

    %__MODULE__{points: points}
  end

  def advance(%__MODULE__{} = towers, participants, elapsed_ms) do
    members =
      for %Participant{guid: guid, team: team} = participant <- participants,
          id = nearest(towers, participant),
          not is_nil(id),
          into: %{},
          do: {guid, {id, team}}

    counts = Enum.frequencies(Map.values(members))

    points =
      Map.new(towers.points, fn {id, point} ->
        {id,
         CapturePoint.advance(point, Map.get(counts, {id, :alliance}, 0), Map.get(counts, {id, :horde}, 0), elapsed_ms)}
      end)

    %{towers | points: points, members: members}
  end

  def counts(%__MODULE__{points: points}) do
    points |> Map.values() |> Enum.map(&CapturePoint.owner/1) |> Enum.reject(&is_nil/1) |> Enum.frequencies()
  end

  def buff(%__MODULE__{} = towers, team), do: Plaguelands.buff(team, Map.get(counts(towers), team, 0))

  def world_states(%__MODULE__{} = towers) do
    counts = counts(towers)
    states = [{2327, Map.get(counts, :alliance, 0)}, {2328, Map.get(counts, :horde, 0)}]

    states ++
      Enum.flat_map(Enum.sort(Plaguelands.towers()), fn {id, _definition} ->
        phase =
          case towers.points[id] do
            %CapturePoint{phase: phase} -> phase
            nil -> :neutral
          end

        Plaguelands.tower_states(id, phase)
      end)
  end

  def slider_states(%__MODULE__{} = towers, guid) do
    case towers.members[guid] do
      {id, _team} -> CapturePoint.enter_states(Map.fetch!(towers.points, id))
      nil -> [{2426, 0}]
    end
  end

  def ownership_changes(%__MODULE__{} = previous, %__MODULE__{} = current) do
    for {id, point} <- Enum.sort(current.points),
        before <- [CapturePoint.owner(Map.fetch!(previous.points, id))],
        after_team <- [CapturePoint.owner(point)],
        before != after_team,
        do: {id, before, after_team}
  end

  def phase_changes(%__MODULE__{} = previous, %__MODULE__{} = current) do
    for {id, point} <- Enum.sort(current.points),
        before <- [Map.fetch!(previous.points, id).phase],
        before != point.phase,
        do: {id, before, point.phase}
  end

  def capture_recipients(participants, id, team) when team in [:alliance, :horde] do
    position = Plaguelands.credit_position(id, team)

    for %Participant{
          guid: guid,
          team: ^team,
          world: %WorldRef{map_id: 0, instance_id: nil},
          eligible?: true,
          position: target
        } <- participants,
        Math.distance(position, target) <= 100,
        do: guid
  end

  def capture_recipients(_participants, _id, _team), do: []

  def updates(%__MODULE__{} = previous, %__MODULE__{} = current, guid) do
    region = if world_states(previous) == world_states(current), do: [], else: world_states(current)
    meter = meter_updates(previous, current, guid, region != [])
    region ++ meter
  end

  defp meter_updates(previous, current, guid, region_changed?) do
    case {previous.members[guid], current.members[guid]} do
      {nil, nil} ->
        []

      {{id, _team}, nil} ->
        CapturePoint.leave_states(Map.fetch!(previous.points, id))

      {{id, _team}, {id, _new_team}} ->
        old_point = Map.fetch!(previous.points, id)
        point = Map.fetch!(current.points, id)

        if region_changed? or CapturePoint.slider_changed?(old_point, point),
          do: [CapturePoint.position_state(point)],
          else: []

      {_previous, {id, _team}} ->
        CapturePoint.enter_states(Map.fetch!(current.points, id))
    end
  end

  defp nearest(%__MODULE__{points: points}, %Participant{
         eligible?: true,
         team: team,
         world: %WorldRef{map_id: 0, instance_id: nil},
         position: position
       })
       when team in [:alliance, :horde] do
    points
    |> Enum.flat_map(fn {id, point} ->
      {x, y, z, _orientation} = Plaguelands.towers()[id].position
      distance = Math.distance(position, {x, y, z})
      if distance < point.template.radius, do: [{distance, id}], else: []
    end)
    |> Enum.min(fn -> nil end)
    |> case do
      {_distance, id} -> id
      nil -> nil
    end
  end

  defp nearest(_towers, _participant), do: nil
end
