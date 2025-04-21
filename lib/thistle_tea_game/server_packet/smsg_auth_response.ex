defmodule ThistleTeaGame.ServerPacket.SmsgAuthResponse do
  use ThistleTeaGame.ServerPacket, opcode: :SMSG_AUTH_RESPONSE

  @result_auth_ok 0x0C
  @result_auth_wait_queue 0x1B

  defstruct [
    :result,
    :billing_time,
    :billing_flags,
    :billing_rested,
    :queue_position
  ]

  @impl ServerPacket
  def encode(%__MODULE__{
        result: result,
        billing_time: billing_time,
        billing_flags: billing_flags,
        billing_rested: billing_rested,
        queue_position: queue_position
      }) do
    (<<result::little-size(8)>> <>
       case result do
         @result_auth_ok ->
           <<billing_time::little-size(32), billing_flags::little-size(8),
             billing_rested::little-size(32)>>

         @result_auth_wait_queue ->
           <<queue_position::little-size(32)>>

         _ ->
           <<>>
       end)
    |> ServerPacket.build(@opcode)
  end
end
