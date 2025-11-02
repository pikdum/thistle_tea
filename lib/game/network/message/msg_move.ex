defmodule ThistleTea.Game.Network.Message.MsgMove do
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_JUMP
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_JUMP]

  alias ThistleTea.Game.Network.ClientMessage
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject

  require Logger

  @spell_failed_moving 0x2E

  defstruct [
    :opcode,
    :payload
  ]

  @impl ClientMessage
  def handle(
        %__MODULE__{opcode: opcode, payload: payload} = message,
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

      new_state =
        if x0 != x1 or y0 != y1 or z0 != z1 do
          SpatialHash.update(:players, state.guid, self(), map, x1, y1, z1)

          Map.put(state, :character, character)
          |> Message.CmsgCancelCast.cancel_spell(@spell_failed_moving)
        else
          Map.put(state, :character, character)
        end

      new_state
      |> randomize_equipment(opcode)
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
    for pid <- Map.get(state, :player_pids, []) do
      if pid != self() do
        GenServer.cast(pid, {:send_packet, message.opcode, state.packed_guid <> message.payload})
      end
    end

    state
  end

  defp randomize_equipment(state, opcode) do
    if opcode === @msg_move_jump do
      character = ThistleTea.Character.generate_and_assign_equipment(state.character)

      packet =
        %UpdateObject{
          update_type: :values,
          object_type: :player
        }
        |> struct(Map.from_struct(character))
        |> UpdateObject.to_packet()

      # item packets
      UpdateObject.get_item_packets(character.player)
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
