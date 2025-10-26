defmodule ThistleTea.Game.Message.SmsgAuthResponse do
  use ThistleTea.Opcodes, [:SMSG_AUTH_RESPONSE]

  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgAuthResponse
  alias ThistleTea.Game.Packet

  @result_auth_ok 0x0C
  @result_auth_wait_queue 0x1B
  defstruct [
    :result,
    :billing_time,
    :billing_flags,
    :billing_rested,
    :queue_position
  ]

  defimpl Message do
    def to_binary(message), do: SmsgAuthResponse.to_binary(message)
    def to_packet(message), do: SmsgAuthResponse.to_packet(message)
  end

  def to_binary(%__MODULE__{
        result: result,
        billing_time: billing_time,
        billing_flags: billing_flags,
        billing_rested: billing_rested,
        queue_position: queue_position
      }) do
    <<result::little-size(8)>> <>
      case result do
        @result_auth_ok ->
          <<billing_time::little-size(32), billing_flags::little-size(8), billing_rested::little-size(32)>>

        @result_auth_wait_queue ->
          <<queue_position::little-size(32)>>

        _ ->
          <<>>
      end
  end

  def to_packet(message) do
    to_binary(message)
    |> Packet.build(@smsg_auth_response)
  end
end
