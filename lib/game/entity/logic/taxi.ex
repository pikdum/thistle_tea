defmodule ThistleTea.Game.Entity.Logic.Taxi do
  @moduledoc """
  Pure character transitions for entering and finishing a taxi flight.
  """
  import Bitwise, only: [&&&: 2, bnot: 1, |||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement

  @remove_client_control_flag 0x00000004
  @taxi_flight_flag 0x00100000
  @taxi_flags @remove_client_control_flag ||| @taxi_flight_flag
  @flight_speed 32.0

  def start(
        %Character{unit: %Unit{} = unit, internal: %Internal{}} = character,
        itinerary,
        %Node{} = destination,
        mount_display_id,
        token,
        now
      )
      when is_map(itinerary) and is_integer(mount_display_id) and mount_display_id > 0 and is_reference(token) and
             is_integer(now) do
    positions = Enum.map(itinerary.nodes, & &1.position)
    path_ids = Enum.map(itinerary.paths, & &1.id)
    source_node_id = hd(itinerary.paths).source_node_id
    destination_node_id = List.last(itinerary.paths).destination_node_id

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
      destination_position: destination.position,
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
    character = Movement.halt(character, now)
    {_old_x, _old_y, _old_z, orientation} = character.movement_block.position
    movement_block = %{character.movement_block | position: {x, y, z, orientation}}
    unit = %{unit | flags: (unit.flags || 0) &&& bnot(@taxi_flags), mount_display_id: 0}
    internal = %{character.internal | taxi_flight: nil}

    %{character | unit: unit, internal: internal, movement_block: movement_block}
    |> Core.mark_broadcast_update()
  end

  def finish(%Character{} = character, _now), do: character

  def active?(%Character{internal: %Internal{taxi_flight: %Flight{}}}), do: true
  def active?(%Character{}), do: false
end
