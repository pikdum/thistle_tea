defmodule ThistleTea.Game.Entity.Logic.Taxi do
  @moduledoc """
  Pure character transitions for starting, suspending, resuming, and finishing taxi flights.
  """
  import Bitwise, only: [&&&: 2, bnot: 1, |||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Mount
  alias ThistleTea.Game.Entity.Logic.Movement

  @remove_client_control_flag 0x00000004
  @taxi_flight_flag 0x00100000
  @taxi_flags @remove_client_control_flag ||| @taxi_flight_flag
  @flight_speed 32.0

  def start(
        %Character{unit: %Unit{}, internal: %Internal{}} = character,
        itinerary,
        %Node{} = destination,
        mount_display_id,
        token,
        now
      )
      when is_map(itinerary) and is_integer(mount_display_id) and mount_display_id >= 0 and is_reference(token) and
             is_integer(now) do
    character = character |> prepare_auras(now) |> Mount.dismount(now) |> ExtraAttacks.clear() |> Falling.reset()
    unit = character.unit
    positions = Enum.map(itinerary.nodes, & &1.position)
    path_ids = Enum.map(itinerary.paths, & &1.id)
    source_node_id = hd(itinerary.paths).source_node_id
    destination_node_id = destination.id

    character =
      %{
        character
        | unit: %{unit | flags: (unit.flags || 0) ||| @taxi_flags, mount_display_id: mount_display_id},
          player: %{character.player | coinage: character.player.coinage - itinerary.total_cost}
      }
      |> Movement.move_along_path(positions, [velocity: @flight_speed, flying?: true, run?: true], now)

    flight = %Flight{
      token: token,
      path_ids: path_ids,
      source_node_id: source_node_id,
      destination_node_id: destination_node_id,
      destination_position: List.last(positions),
      mount_display_id: mount_display_id,
      started_at: now,
      duration_ms: character.movement_block.duration
    }

    character = %{character | internal: %{character.internal | taxi_flight: flight}}
    {character, effects} = Effects.drain(character)
    {Core.mark_broadcast_update(character), effects}
  end

  def finish(
        %Character{
          unit: %Unit{} = unit,
          internal: %Internal{taxi_flight: %Flight{destination_position: {x, y, z}}},
          movement_block: %MovementBlock{}
        } = character,
        now
      )
      when is_integer(now) do
    character = Movement.finish(character, now)
    {_old_x, _old_y, _old_z, orientation} = character.movement_block.position
    movement_block = %{character.movement_block | position: {x, y, z, orientation}}
    unit = %{unit | flags: (unit.flags || 0) &&& bnot(@taxi_flags), mount_display_id: 0}
    internal = %{character.internal | taxi_flight: nil}

    %{character | unit: unit, internal: internal, movement_block: movement_block}
    |> Falling.reset()
    |> Core.mark_broadcast_update()
  end

  def finish(%Character{} = character, _now), do: character

  def pause(%Character{internal: %Internal{taxi_flight: %Flight{remaining_nodes: [_ | _]}}} = character, _now),
    do: character

  def pause(%Character{internal: %Internal{taxi_flight: %Flight{} = flight}} = character, now) do
    case Movement.resume_spline(character, now) do
      %Character{movement_block: movement} ->
        character = Movement.finish(character, now)

        flight = %{
          flight
          | token: nil,
            started_at: nil,
            duration_ms: movement.duration,
            remaining_nodes: movement.spline_nodes
        }

        %{character | internal: %{character.internal | taxi_flight: flight}}

      nil ->
        if is_integer(character.internal.movement_start_time), do: finish(character, now), else: cancel(character, now)
    end
  end

  def pause(%Character{} = character, _now), do: character

  def resume(
        %Character{internal: %Internal{taxi_flight: %Flight{remaining_nodes: [_ | _] = nodes} = flight}} = character,
        token,
        now
      )
      when is_reference(token) and is_integer(now) do
    if Death.alive?(character) do
      opts = [flying?: true, run?: true]
      character = Movement.start_timed_path(character, nodes, flight.duration_ms, now, opts)
      resume_started_path(character, flight, token, now, opts)
    else
      {cancel(character, now), []}
    end
  end

  def resume(%Character{} = character, _token, _now), do: {character, []}

  defp resume_started_path(
         %Character{internal: %Internal{movement_start_time: nil}} = character,
         _flight,
         _token,
         now,
         _opts
       ), do: {finish(character, now), []}

  defp resume_started_path(%Character{} = character, %Flight{} = flight, token, now, opts) do
    flight = %{flight | token: token, started_at: now, remaining_nodes: nil}

    unit = %{
      character.unit
      | flags: (character.unit.flags || 0) ||| @taxi_flags,
        mount_display_id: flight.mount_display_id
    }

    character = %{character | unit: unit, internal: %{character.internal | taxi_flight: flight}}
    {Core.mark_broadcast_update(character), [Effects.monster_move(opts)]}
  end

  def cancel(%Character{internal: %Internal{taxi_flight: %Flight{}}} = character, now) do
    character = Movement.finish(character, now)
    unit = %{character.unit | flags: (character.unit.flags || 0) &&& bnot(@taxi_flags), mount_display_id: 0}
    internal = %{character.internal | taxi_flight: nil}

    %{character | unit: unit, internal: internal} |> Falling.reset() |> Core.mark_broadcast_update()
  end

  def cancel(%Character{} = character, _now), do: character

  def active?(%Character{internal: %Internal{taxi_flight: %Flight{}}}), do: true
  def active?(%Character{}), do: false

  def disallowed_form?(%Character{unit: %Unit{shapeshift_form: form}}), do: form not in [nil, 0, 17, 18, 19, 28, 30]

  defp prepare_auras(character, now) do
    types = if disallowed_form?(character), do: [:mod_stealth, :mod_shapeshift, :transform], else: [:mod_stealth]
    {character, effects} = Aura.remove_aura_types(character, types, now)
    Effects.enqueue(character, effects)
  end
end
