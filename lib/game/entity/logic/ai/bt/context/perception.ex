defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception do
  @moduledoc """
  Immutable world observations captured for one behavior-tree tick.
  """

  alias __MODULE__.Observation

  @enforce_keys [:now, :origin, :entities, :nearby]
  defstruct [:now, :origin, :entities, :nearby]

  def empty(now \\ 0), do: new(now, nil, %{}, %{mobs: [], players: [], game_objects: []})

  def new(now, origin, entities, nearby) when is_integer(now) and is_map(entities) and is_map(nearby) do
    %__MODULE__{now: now, origin: origin, entities: entities, nearby: nearby}
  end

  def position(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{position: position} -> position
      nil -> nil
    end
  end

  def grounded_position(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{grounded_position: position} -> position
      nil -> nil
    end
  end

  def projected_position(%__MODULE__{} = perception, guid, horizon_ms)
      when is_integer(horizon_ms) and horizon_ms >= 0 do
    case observation(perception, guid) do
      %Observation{} = observation -> project(observation, horizon_ms, perception.now)
      nil -> nil
    end
  end

  def distance(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{distance: distance} -> distance
      nil -> nil
    end
  end

  def moving?(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{moving?: moving?} -> moving?
      nil -> false
    end
  end

  def metadata(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{metadata: metadata} -> metadata
      nil -> nil
    end
  end

  def actor(%__MODULE__{} = perception, guid) when is_integer(guid) do
    case metadata(perception, guid) do
      metadata when is_map(metadata) -> Map.put(metadata, :guid, guid)
      nil -> %{guid: guid}
    end
  end

  def nearby(%__MODULE__{nearby: nearby}, kind, radius)
      when kind in [:mobs, :players, :game_objects] and is_number(radius) do
    nearby
    |> Map.get(kind, [])
    |> Enum.filter(fn {_guid, distance} -> is_number(distance) and distance <= radius end)
  end

  def nearby(%__MODULE__{}, _kind, _radius), do: []

  def line_of_sight?(%__MODULE__{} = perception, guid) do
    case observation(perception, guid) do
      %Observation{line_of_sight?: visible?} -> visible?
      nil -> true
    end
  end

  defp observation(%__MODULE__{entities: entities}, guid), do: Map.get(entities, guid)

  defp project(
         %Observation{
           grounded_position: {world, x, y, z},
           metadata: %{movement_velocity: {vx, vy, vz}, moving_until: moving_until}
         },
         horizon_ms,
         now
       )
       when is_number(vx) and is_number(vy) and is_number(vz) and is_integer(moving_until) and moving_until > now do
    seconds = horizon_ms / 1_000
    {world, x + vx * seconds, y + vy * seconds, z + vz * seconds}
  end

  defp project(%Observation{grounded_position: position}, _horizon_ms, _now) when is_tuple(position), do: position
  defp project(%Observation{position: position}, _horizon_ms, _now), do: position
end
