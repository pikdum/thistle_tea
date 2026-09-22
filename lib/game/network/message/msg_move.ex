defmodule ThistleTea.Game.Network.Message.MsgMove do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_MOVE_JUMP
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_KNOCK_BACK]

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Movement

  defstruct [:opcode, :payload]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state), do: Movement.handle(message, state)

  @impl ClientMessage
  def from_binary(payload), do: %__MODULE__{payload: payload}

  def to_packet(guid, payload, @msg_move_knock_back) do
    %Message.MsgMoveKnockBack{guid: guid, movement_block: MovementBlock.from_binary(payload)}
  end

  def to_packet(guid, payload, opcode), do: Packet.build(BinaryUtils.pack_guid(guid) <> payload, opcode)
end
