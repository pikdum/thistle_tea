defmodule ThistleTea.Game.Network.Message.MsgMove do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_JUMP
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_KNOCK_BACK, :MSG_MOVE_STOP, :MSG_MOVE_HEARTBEAT]

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Movement

  defstruct [:opcode, :payload]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Movement.handle(message, state)

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{payload: payload}

  def from_final_movement(payload) do
    movement = MovementBlock.from_binary(payload)
    moving? = Bitwise.band(movement.movement_flags || 0, 0x3F) != 0 or MovementBlock.airborne?(movement)
    %__MODULE__{payload: payload, opcode: if(moving?, do: @msg_move_heartbeat, else: @msg_move_stop)}
  end

  def to_packet(guid, payload, @msg_move_knock_back) do
    %Message.MsgMoveKnockBack{guid: guid, movement_block: MovementBlock.from_binary(payload)}
  end

  def to_packet(guid, payload, opcode), do: Packet.build(BinaryUtils.pack_guid(guid) <> payload, opcode)
end
