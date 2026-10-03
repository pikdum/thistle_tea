defmodule ThistleTea.Game.World.Entity.GameObject.ElementalRift do
  @moduledoc """
  Runs an Elemental Invasion rift (vmangos `elemental_invasion_riftAI`) for as
  long as its element's rift event keeps it spawned. Every seventy seconds it
  calls out invaders until its element's stage count stands, each sent to
  roam a walkable spot fifteen to sixty-five yards out for up to an hour, and
  it reports the ones slain to `World.System.ElementalInvasion`.
  """

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal.Rift
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameEvent.ElementalInvasion, as: Invasion
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.System.ElementalInvasion, as: InvasionSystem

  @upkeep :rift_upkeep
  @first_upkeep_ms 500
  @upkeep_ms 70_000
  @invader_lifetime_ms 3_600_000
  @timed_or_dead_despawn 1
  @roam_radius 65.0
  @nearest_roam 15.0
  @roam_attempts 20
  @wander_distance 30.0

  def start(%GameObject{object: %{entry: entry}} = state) do
    case Invasion.rift_element(entry) do
      %Invasion.Element{name: name} ->
        Process.send_after(self(), @upkeep, @first_upkeep_ms)
        %{state | internal: %{state.internal | rift: %Rift{element: name}}}

      nil ->
        state
    end
  end

  def upkeep(%GameObject{internal: %{rift: %Rift{element: name} = rift}} = state) do
    Process.send_after(self(), @upkeep, @upkeep_ms)
    element = Enum.find(Invasion.elements(), &(&1.name == name))
    missing = Invasion.invaders(InvasionSystem.stage(element)) - MapSet.size(rift.invaders)
    Enum.reduce(1..missing//1, state, fn _invader, state -> call_invader(state, element) end)
  end

  def upkeep(%GameObject{} = state), do: state

  def summon_event(%GameObject{internal: %{rift: %Rift{} = rift} = internal} = state, %SummonEvent{} = event) do
    guid = event.observation.guid

    invaders =
      case event.event do
        :summoned_unit ->
          MapSet.put(rift.invaders, guid)

        :summoned_just_died ->
          InvasionSystem.invader_slain(rift.element)
          MapSet.delete(rift.invaders, guid)

        :summoned_just_despawn ->
          MapSet.delete(rift.invaders, guid)

        _other ->
          rift.invaders
      end

    %{state | internal: %{internal | rift: %{rift | invaders: invaders}}}
  end

  def summon_event(%GameObject{} = state, %SummonEvent{}), do: state

  defp call_invader(%GameObject{internal: %{world: world}} = state, %Invasion.Element{invader: entry}) do
    {x, y, z, _orientation} = state.movement_block.position

    summon = %{
      entry: entry,
      position: {x, y, z, 0.0},
      despawn_type: @timed_or_dead_despawn,
      despawn_delay_ms: @invader_lifetime_ms,
      run?: false,
      unique?: false,
      attack_guid: nil,
      script_id: 0,
      home: roam_home(world.map_id, {x, y, z}),
      wander_distance: @wander_distance
    }

    Effects.enqueue(state, Effects.summon_creature(summon, [], nil))
  end

  defp roam_home(map_id, origin) do
    {x, y, z} =
      Enum.reduce_while(1..@roam_attempts, origin, fn _attempt, last ->
        map_id |> Pathfinding.find_random_point_around_circle(origin, @roam_radius) |> roam_step(origin, last)
      end)

    {x, y, z, :rand.uniform() * 2 * :math.pi()}
  end

  defp roam_step({px, py, _pz} = point, {ox, oy, _oz}, _last) do
    if Math.distance({ox, oy, 0.0}, {px, py, 0.0}) > @nearest_roam, do: {:halt, point}, else: {:cont, point}
  end

  defp roam_step(_none, _origin, last), do: {:cont, last}
end
