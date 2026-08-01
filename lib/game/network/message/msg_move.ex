defmodule ThistleTea.Game.Network.Message.MsgMove do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_JUMP

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.ClientMessage
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility

  @spell_failed_moving 0x2E
  @client_projection_ms 750

  defstruct [
    :opcode,
    :payload
  ]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{character: %Character{internal: %{taxi_flight: %Flight{}}}} = state), do: state

  def handle(%__MODULE__{}, %{server_movement: server_movement} = state) when not is_nil(server_movement), do: state

  def handle(
        %__MODULE__{payload: payload, opcode: opcode},
        %{ready: true, guid: player_guid, active_mover_guid: mover_guid, character: %Character{} = character} = state
      )
      when is_integer(mover_guid) and mover_guid > 0 and mover_guid != player_guid do
    if Companion.control_guid(character) == mover_guid do
      case Entity.pid(mover_guid) do
        pid when is_pid(pid) -> send(pid, {:controlled_move, payload, opcode})
        _ -> nil
      end
    end

    state
  end

  def handle(
        %__MODULE__{payload: payload} = message,
        %{
          ready: true,
          guid: player_guid,
          active_mover_guid: mover_guid,
          character: %Character{movement_block: %MovementBlock{} = movement_block, unit: %Unit{}} = character
        } = state
      )
      when mover_guid in [nil, player_guid] do
    movement_block = MovementBlock.from_binary(payload, movement_block)

    case Transports.reconcile(character, movement_block) do
      {:ok, movement_block} ->
        state = MovementControl.track_transport_boarding(state, character.movement_block, movement_block)
        handle_player_movement(message, state, movement_block)

      {:error, _reason} ->
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    %__MODULE__{
      payload: payload
    }
  end

  defp handle_player_movement(
         message,
         %{character: %Character{movement_block: %MovementBlock{} = previous_movement_block, unit: %Unit{} = unit}} =
           state,
         %MovementBlock{} = movement_block
       ) do
    character = state.character
    character = %{character | movement_block: movement_block, unit: %{unit | stand_state: 0}}
    %{internal: %{world: world}} = character
    %MovementBlock{position: {x1, y1, z1, orientation}} = movement_block
    now = Time.now()
    movement_velocity = MovementBlock.client_velocity(movement_block)

    position_changed? = MovementBlock.position_changed?(previous_movement_block, movement_block)
    translating? = MovementBlock.translating?(movement_block)

    presence_metadata = %{
      orientation: orientation,
      movement_velocity: movement_velocity,
      airborne?: MovementBlock.airborne?(movement_block),
      last_move_at: now,
      moving_until: if(translating?, do: now + @client_projection_ms, else: now)
    }

    moved? = position_changed? or translating?
    character = interrupt_auras(character, moved?)
    character = interrupt_water_auras(character, movement_block, state.character.movement_block)

    Presence.relocate_client(
      character,
      presence_metadata,
      movement_velocity,
      now,
      @client_projection_ms
    )

    new_state =
      if moved? do
        AggroProbe.notify_player_moved(state.guid, world, {x1, y1, z1})
        ChaseWatch.notify_moved(state.guid, {x1, y1, z1})

        %{state | character: character}
        |> Spellcasting.cancel(@spell_failed_moving)
        |> PlayerRest.check_tavern_exit()
        |> PlayerExploration.check_movement(now)
      else
        %{state | character: character}
      end

    new_state
    |> Visibility.refresh_player()
    |> broadcast(message)
  end

  defp broadcast(state, message) do
    Packet.build(state.packed_guid <> message.payload, message.opcode)
    |> World.broadcast_packet(state.character, include_self?: false, recipients: Map.get(state, :player_guids))

    state
  end

  defp interrupt_auras(character, position_changed?) do
    mask = if position_changed?, do: AuraLogic.interrupt_mask(:move), else: AuraLogic.interrupt_mask(:turn)
    auras_before = character.unit.auras
    {character, events} = AuraLogic.remove_with_interrupt_flags(character, mask, Time.now())

    character =
      character
      |> Effects.enqueue(events)
      |> EventSink.emit_pending()

    if character.unit.auras != auras_before do
      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character)
    end

    character
  end

  defp interrupt_water_auras(character, current, previous) do
    if MovementBlock.swimming?(previous) and not MovementBlock.swimming?(current) do
      {character, events} =
        AuraLogic.remove_with_interrupt_flags(character, AuraLogic.interrupt_mask(:above_water), Time.now())

      character |> Effects.enqueue(events) |> EventSink.emit_pending()
    else
      character
    end
  end
end
