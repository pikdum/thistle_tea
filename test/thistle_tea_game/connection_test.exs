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
        <<0, 177, 237, 1, 0, 0, 243, 22, 0, 0, 0, 0, 0, 0, 80, 73, 75, 68, 85, 77, 0, 252, 169,
          106, 101, 165, 171, 232, 120, 123, 66, 241, 211, 142, 185, 95, 91, 245, 168, 181, 8,
          100, 191, 123, 182, 86, 1, 0, 0, 120, 156, 117, 204, 189, 14, 194, 48, 12, 4, 224, 242,
          30, 188, 12, 97, 64, 149, 200, 66, 195, 140, 76, 226, 34, 11, 199, 169, 140, 203, 79,
          159, 30, 22, 36, 6, 115, 235, 119, 119, 129, 105, 89, 64, 203, 105, 51, 103, 163, 38,
          199, 190, 91, 213, 199, 122, 223, 125, 18, 190, 22, 192, 140, 113, 36, 228, 18, 73, 168,
          194, 228, 149, 72, 10, 201, 197, 61, 216, 182, 122, 6, 75, 248, 52, 15, 21, 70, 115,
          103, 187, 56, 204, 122, 199, 151, 139, 189, 220, 38, 204, 254, 48, 66, 214, 230, 202, 1,
          168, 184, 144, 128, 81, 252, 183, 164, 80, 112, 184, 18, 243, 63, 38, 65, 253, 181, 55,
          144, 25, 102, 143>>

      conn =
        %Connection{packet_stream: packet_stream}
        |> Connection.enqueue_packets()

      [packet | _] = conn.packet_queue
      assert packet.opcode == @cmsg_auth_session
      assert packet.size == 177
      {:ok, decoded} = ClientPacket.decode(packet)
      assert %ClientPacket.CmsgAuthSession{} = decoded
      {:error, conn} = Packet.handle(decoded, conn)
    end
  end
end
