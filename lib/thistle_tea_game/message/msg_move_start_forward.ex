defmodule ThistleTeaGame.Message.MsgMoveStartForward do
  use ThistleTeaGame.ServerPacket
  use ThistleTeaGame.ClientPacket
  # TODO: how can i make this handle multiple opcodes with the same code?
  # issues: single struct, so single protocol impls
  # single module, so single decode lookup
  # so if i had a more generic struct, i could have handle + encode work
  # %MsgMove{} or similar
  # could go back to hardcoded decode table
  # or could have hardcoded + what i have now
  #
  # what does the opcode opt actually do?
  # client_packet - just @opcode function, not really used
  # server_packet - used in encode to build the packet
  #
  # could we abstract that out for use cases like this?
  # should be kinda rare

  defstruct [:guid, :opcode, :movement_info]

  @impl ClientPacket
  def handle(
        %__MODULE__{opcode: opcode, movement_info: movement_info} = packet,
        %Connection{} = conn
      ) do
    effect = %Effect.BroadcastPacketToRange{
      origin: {x, y, z},
      range: 200,
      packet: fn player ->
        %__MODULE__{
          guid: player.guid,
          opcode: opcode,
          movement_info: movement_info
        }
      end
    }
  end

  @impl ClientPacket
  def decode(%ClientPacket{opcode: opcode, payload: payload}) do
    {:ok,
     %__MODULE__{
       opcode: opcode,
       movement_info: payload
     }}
  end

  @impl ServerPacket
  def encode(%__MODULE__{
        opcode: opcode,
        guid: guid,
        movement_info: movement_info
      }) do
    (guid <> movement_info)
    |> ServerPacket.build(opcode)
  end
end
