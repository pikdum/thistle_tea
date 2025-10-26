defmodule ThistleTea.Game.Message.MsgMove do
  use ThistleTea.Game.ClientMessage, :MSG_MOVE_JUMP
  use ThistleTea.Opcodes, [:MSG_MOVE_JUMP]

  alias ThistleTea.Game.ClientMessage
  alias ThistleTea.Game.FieldStruct.MovementBlock
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Utils.UpdateObject

  require Logger

  @spell_failed_moving 0x2E

  defstruct [
    :opcode,
    :payload
  ]

  @impl ClientMessage
  def handle(%__MODULE__{opcode: opcode, payload: payload} = message, %{ready: true} = state) do
    with %MovementBlock{position: {x0, y0, z0, _}} <- state.character.movement,
         %MovementBlock{position: {x1, y1, z1, _}} = movement <-
           MovementBlock.from_binary(payload, state.character.movement),
         %{map: map} = character <- state.character |> Map.put(:movement, movement) do
      if x0 != x1 or y0 != y1 or z0 != z1 do
        SpatialHash.update(:players, state.guid, self(), map, x1, y1, z1)

        Map.put(state, :character, character)
        |> Message.CmsgCancelCast.cancel_spell(@spell_failed_moving)
      else
        Map.put(state, :character, character)
      end
    else
      nil -> state
    end
    |> randomize_equipment(opcode)
    |> broadcast(message)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    %__MODULE__{
      payload: payload
    }
  end

  defp broadcast(state, message) do
    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_packet, message.opcode, state.packed_guid <> message.payload})
      end
    end

    state
  end

  defp randomize_equipment(state, opcode) do
    if opcode === @msg_move_jump do
      character = Map.put(state.character, :equipment, Message.CmsgCharCreate.generate_random_equipment())

      update_object =
        character |> ThistleTea.Character.get_update_fields() |> Map.put(:update_type, :values)

      packet = UpdateObject.to_packet(update_object)

      # item packets
      UpdateObject.get_item_packets(character.equipment)
      |> Enum.each(fn packet -> Util.send_update_packet(packet) end)

      for pid <- Map.get(state, :player_pids, []) do
        GenServer.cast(pid, {:send_update_packet, packet})
      end

      Map.put(state, :character, character)
    else
      state
    end
  end
end
