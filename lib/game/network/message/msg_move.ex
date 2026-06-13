defmodule ThistleTea.Game.Network.Message.MsgMove do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_JUMP

  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Network.ClientMessage
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility

  require Logger

  @spell_failed_moving 0x2E
  @move_recency_ms 750

  defstruct [
    :opcode,
    :payload
  ]

  @impl ClientMessage
  def handle(
        %__MODULE__{payload: payload} = message,
        %{
          ready: true,
          character: %Character{movement_block: %MovementBlock{} = movement_block, unit: %Unit{} = unit} = character
        } = state
      ) do
    movement_block = MovementBlock.from_binary(payload, movement_block)

    if movement_block do
      character = %{character | movement_block: movement_block, unit: %{unit | stand_state: 0}}
      %{internal: %{map: map}} = character
      %MovementBlock{position: {x0, y0, z0, _}} = state.character.movement_block
      %MovementBlock{position: {x1, y1, z1, _}} = movement_block
      position_changed? = x0 != x1 or y0 != y1 or z0 != z1
      character = interrupt_auras(character, position_changed?)

      new_state =
        if position_changed? do
          SpatialHash.update(:players, state.guid, map, x1, y1, z1)
          Metadata.update(state.guid, %{moving_until: Time.now() + @move_recency_ms})
          AggroProbe.notify_player_moved(state.guid, map, {x1, y1, z1})
          ChaseWatch.notify_moved(state.guid, {x1, y1, z1})

          %{state | character: character}
          |> Spellcasting.cancel(@spell_failed_moving)
        else
          %{state | character: character}
        end

      new_state
      |> Visibility.refresh_player()
      |> broadcast(message)
    else
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
      |> Event.enqueue(events)
      |> EventSink.emit_pending()

    if character.unit.auras != auras_before do
      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character)
    end

    character
  end
end
