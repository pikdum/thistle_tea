defmodule ThistleTeaGame.ServerPacket.SmsgAuthResponseTest do
  use ExUnit.Case

  alias ThistleTeaGame.ServerPacket.SmsgAuthResponse

  describe "encode/1" do
    test "Authentication failed" do
      # Full packet
      # 00 03       -> size (3 bytes)
      # EE 01       -> opcode (0x01EE = 494)
      # 0D          -> result: AUTH_FAILED (0x0D)

      packet = %SmsgAuthResponse{
        result: 0x0D
      }

      %ThistleTeaGame.ServerPacket{payload: payload} = SmsgAuthResponse.encode(packet)

      assert payload == <<0x0D>>
    end

    test "Client told to wait in queue" do
      # Full packet
      # 00 07             -> size (7 bytes)
      # EE 01             -> opcode (0x01EE = 494)
      # 1B                -> result: AUTH_WAIT_QUEUE (0x1B)
      # EF BE AD DE       -> queue_position: 0xDEADBEEF

      packet = %SmsgAuthResponse{
        result: 0x1B,
        queue_position: 0xDEADBEEF
      }

      %ThistleTeaGame.ServerPacket{payload: payload} = SmsgAuthResponse.encode(packet)

      assert payload == <<0x1B, 0xEF, 0xBE, 0xAD, 0xDE>>
    end

    test "Client can join" do
      # Full packet
      # 00 0C                   -> size (12 bytes)
      # EE 01                   -> opcode (0x01EE = 494)
      # 0C                      -> result: AUTH_OK (0x0C)
      # EF BE AD DE             -> billing_time: 0xDEADBEEF
      # 00                      -> billing_flags
      # 00 00 00 00             -> billing_rested

      packet = %SmsgAuthResponse{
        result: 0x0C,
        billing_time: 0xDEADBEEF,
        billing_flags: 0x00,
        billing_rested: 0x00000000
      }

      %ThistleTeaGame.ServerPacket{payload: payload} = SmsgAuthResponse.encode(packet)

      assert payload ==
               <<0x0C, 0xEF, 0xBE, 0xAD, 0xDE, 0x00, 0x00, 0x00, 0x00, 0x00>>
    end
  end
end
