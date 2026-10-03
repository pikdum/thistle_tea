defmodule ThistleTea.Game.World.Entity.GameObject.GhostMagnet do
  @moduledoc """
  Runs a Ghost Magnet (vmangos `go_ghost_magnetAI`) from Ghost-o-plasm Round
  Up (6134) in Desolace. A magnet set where no other magnet's aura glows
  within thirty yards raises its own aura for two minutes, and for those two
  minutes it calls Magrami Spectres from walkable spots up to forty yards
  out: eight of them, the first after five seconds and the rest three to
  eight seconds apart, and a fresh one twenty seconds after any of them
  dies. Each spectre makes the magnet its home and walks to it. Where the
  ground has no navigation mesh, a spectre simply appears somewhere within
  those forty yards.
  """

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal.GhostMagnet, as: Magnet
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Pathfinding

  @magnet 177_746
  @aura 177_749
  @spectre 11_560

  @call :ghost_magnet_call
  @replace :ghost_magnet_replace
  @aura_reach 30.0
  @calling_ms 120_000
  @spectres 8
  @first_call_ms 5_000
  @call_gap_ms 3_000..8_000
  @replace_ms 20_000
  @spectre_lifetime_ms 120_000
  @timed_or_dead_despawn 1
  @call_radius 40.0
  @contact_distance 1.5
  @arrival_point 2
  @pathfind 1
  @inform_arrival 2

  def start(%GameObject{object: %{entry: @magnet}, internal: %{world: world} = internal} = state) do
    {x, y, z, _orientation} = state.movement_block.position

    if aura_glowing?(world, {x, y, z}) do
      state
    else
      Process.send_after(self(), @call, @first_call_ms)
      state = %{state | internal: %{internal | magnet: %Magnet{until: Time.now() + @calling_ms, remaining: @spectres}}}

      Effects.enqueue(
        state,
        Effects.summon_game_object(@aura, @calling_ms, owned?: false, position: state.movement_block.position)
      )
    end
  end

  def start(%GameObject{} = state), do: state

  def call(%GameObject{internal: %{magnet: %Magnet{remaining: remaining} = magnet} = internal} = state)
      when remaining > 0 do
    if calling?(magnet) do
      Process.send_after(self(), @call, Enum.random(@call_gap_ms))
      call_spectre(%{state | internal: %{internal | magnet: %{magnet | remaining: remaining - 1}}})
    else
      state
    end
  end

  def call(%GameObject{} = state), do: state

  def replace(%GameObject{internal: %{magnet: %Magnet{} = magnet}} = state) do
    if calling?(magnet), do: call_spectre(state), else: state
  end

  def replace(%GameObject{} = state), do: state

  def summon_event(%GameObject{internal: %{magnet: %Magnet{}}} = state, %SummonEvent{event: :summoned_just_died}) do
    Process.send_after(self(), @replace, @replace_ms)
    state
  end

  def summon_event(%GameObject{} = state, %SummonEvent{}), do: state

  defp calling?(%Magnet{until: until}), do: Time.now() < until

  defp aura_glowing?(world, position) do
    world
    |> then(&World.nearby_units_exact(:game_objects, &1, position, @aura_reach))
    |> Enum.any?(fn {guid, _distance} -> World.entry(guid) == @aura end)
  end

  defp call_spectre(%GameObject{internal: %{world: world}} = state) do
    {x, y, z, _orientation} = state.movement_block.position
    {sx, sy, sz} = Pathfinding.find_random_point_around_circle(world.map_id, {x, y, z}, @call_radius) || near({x, y, z})

    summon = %{
      entry: @spectre,
      position: {sx, sy, sz, 0.0},
      despawn_type: @timed_or_dead_despawn,
      despawn_delay_ms: @spectre_lifetime_ms,
      run?: false,
      unique?: false,
      attack_guid: nil,
      script_id: 0
    }

    Effects.enqueue(state, Effects.summon_creature(summon, walk_to(contact_point({x, y, z}, {sx, sy})), nil))
  end

  defp near({x, y, z}) do
    angle = :rand.uniform() * 2 * :math.pi()
    distance = :rand.uniform() * @call_radius
    {x + distance * :math.cos(angle), y + distance * :math.sin(angle), z}
  end

  defp contact_point({x, y, z}, {sx, sy}) do
    distance = Math.distance({x, y, 0.0}, {sx, sy, 0.0})
    fraction = if distance > @contact_distance, do: @contact_distance / distance, else: 0.0
    {x + (sx - x) * fraction, y + (sy - y) * fraction, z, 0.0}
  end

  defp walk_to(contact) do
    [
      %ScriptStep{command: :set_home_position, position: contact},
      %ScriptStep{
        command: :move_to,
        position: contact,
        datalong3: @pathfind,
        datalong4: @inform_arrival,
        dataint: @arrival_point
      }
    ]
  end
end
