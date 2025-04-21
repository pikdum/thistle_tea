defmodule ThistleTeaGame.ServerPacket.SmsgAuthResponse do
  alias ThisleTeaGame.Connection
  alias ThistleTeaGame.ServerPacket

  @smsg_auth_response 0x1EE
  @result_auth_ok 0x0C

  defstruct [
    :result,
    :billing_time,
    :billing_flags,
    :billing_rested,
    :queue_position
  ]

  # TODO: should this be separate for client/server packets?
  defimpl ThistleTeaGame.Packet do
    def encode(packet), do: ThistleTeaGame.ServerPacket.SmsgAuthResponse.encode(packet)
    def handle(packet), do: nil
  end

  def encode(%__MODULE__{
        result: result,
        billing_time: billing_time,
        billing_flags: billing_flags,
        billing_rested: billing_rested,
        queue_position: queue_position
      }) do
    body =
      <<result::little-size(8)>> <>
        if result == @result_auth_ok do
          <<billing_time::little-size(32), billing_flags::little-size(8),
            billing_rested::little-size(32)>>
        else
          <<queue_position::little-size(32)>>
        end

    size = byte_size(body) + 2
    header = <<size::big-size(16), @smsg_auth_response::little-size(16)>>

    %ServerPacket{
      opcode: @smsg_auth_response,
      payload: body
    }
  end
end
