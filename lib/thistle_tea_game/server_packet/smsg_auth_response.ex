defmodule ThistleTeaGame.ServerPacket.SmsgAuthResponse do
  use ThistleTeaGame.ServerPacket, opcode: 0x1EE

  @result_auth_ok 0x0C

  defstruct [
    :result,
    :billing_time,
    :billing_flags,
    :billing_rested,
    :queue_position
  ]

  @impl ThistleTeaGame.ServerPacket
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

    %ServerPacket{
      opcode: @opcode,
      size: size,
      payload: body
    }
  end
end
