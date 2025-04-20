defmodule ThistleTeaGame.ConnectionTest do
  use ExUnit.Case

  alias ThistleTeaGame.Packet
  alias ThistleTeaGame.ClientPacket
  alias ThistleTeaGame.Connection
  alias ThistleTea.Test.DecryptHeaderRecording

  @cmsg_auth_session 0x1ED

  describe "enqueue_packets/1" do
    test "can queue all packets in recording" do
      for %{input: input, output: output} <- DecryptHeaderRecording.log() do
        conn =
          %Connection{
            session_key: DecryptHeaderRecording.session_key()
          }
          |> Map.merge(input)
          |> Connection.enqueue_packets()

        assert not Enum.empty?(conn.packet_queue)

        [first | _] = conn.packet_queue

        assert output[:header] == <<first.size::big-size(16), first.opcode::little-size(32)>>
      end
    end

    test "can enqueue @cmsg_auth_session" do
      packet_stream =
        <<0, 172, 237, 1, 0, 0, 243, 22, 0, 0, 0, 0, 0, 0, 65, 0, 136, 2, 216, 73, 136, 157, 239,
          5, 37, 187, 193, 171, 167, 138, 219, 164, 251, 163, 231, 126, 103, 172, 234, 198, 86, 1,
          0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 65, 117, 99, 116, 105, 111, 110, 85, 73,
          0, 1, 109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 66, 97,
          116, 116, 108, 101, 102, 105, 101, 108, 100, 77, 105, 110, 105, 109, 97, 112, 0, 1, 109,
          119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 66, 105, 110, 100,
          105, 110, 103, 85, 73, 0, 1, 109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97,
          114, 100, 95, 67, 111, 109, 98, 97, 116, 84, 101, 120, 116, 0, 1, 109, 119, 28, 76, 0,
          0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 67, 114, 97, 102, 116, 85, 73, 0, 1,
          109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 71, 77, 83, 117,
          114, 118, 101, 121, 85, 73, 0, 1, 109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122,
          97, 114, 100, 95, 73, 110, 115, 112, 101, 99, 116, 85, 73, 0, 1, 109, 119, 28, 76, 0, 0,
          0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 77, 97, 99, 114, 111, 85, 73, 0, 1, 109,
          119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 82, 97, 105, 100, 85,
          73, 0, 1, 109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 84,
          97, 108, 101, 110, 116, 85, 73, 0, 1, 109, 119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122,
          122, 97, 114, 100, 95, 84, 114, 97, 100, 101, 83, 107, 105, 108, 108, 85, 73, 0, 1, 109,
          119, 28, 76, 0, 0, 0, 0, 66, 108, 105, 122, 122, 97, 114, 100, 95, 84, 114, 97, 105,
          110, 101, 114, 85, 73, 0, 1, 109, 119, 28, 76, 0, 0, 0, 0>>

      conn =
        %Connection{packet_stream: packet_stream}
        |> Connection.enqueue_packets()

      [packet | _] = conn.packet_queue
      assert packet.opcode == @cmsg_auth_session
      assert packet.size == 172
      {:ok, decoded} = ClientPacket.decode(packet)
      assert %ClientPacket.CmsgAuthSession{} = decoded
      handled = Packet.handle(decoded, conn)
      assert handled == :ok
    end
  end
end
