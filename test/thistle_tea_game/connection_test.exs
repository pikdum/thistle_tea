defmodule ThistleTeaGame.ConnectionTest do
  use ExUnit.Case

  alias ThistleTea.Test.DecryptPacketRecording
  alias ThistleTeaGame.Connection

  describe "decrypt_header/1" do
    test "returns an error when there is not enough data" do
      conn = %Connection{}
      assert {:error, ^conn, :not_enough_data} = Connection.decrypt_header(conn)
    end

    test "can decrypt all headers in recording" do
      for %{input: input, output: output} <- DecryptPacketRecording.log() do
        conn =
          %Connection{
            session_key: DecryptPacketRecording.session_key()
          }
          |> Map.merge(input)

        {:ok, conn, decrypted_header} = Connection.decrypt_header(conn)
        assert decrypted_header == output[:header]
        assert conn.recv_i == output[:recv_i]
        assert conn.recv_j == output[:recv_j]
      end
    end
  end

  describe "decrypt_packets/1" do
    test "can decrypt all packets in recording" do
      for %{input: input, output: output} <- DecryptPacketRecording.log() do
        conn =
          %Connection{
            session_key: DecryptPacketRecording.session_key()
          }
          |> Map.merge(input)
          |> Connection.decrypt_packets()

        assert not Enum.empty?(conn.packet_queue)

        [first | _] = conn.packet_queue

        assert output[:header] == <<first.size::big-size(16), first.opcode::little-size(32)>>
      end
    end
  end
end
