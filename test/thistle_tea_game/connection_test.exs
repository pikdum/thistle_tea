defmodule ThistleTeaGame.ConnectionTest do
  use ExUnit.Case

  alias ThistleTea.Test.EncryptHeaderRecording
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

  describe "encrypt_header/1" do
    test "can encrypt all headers in recording" do
      for %{input: input, output: output} <- EncryptHeaderRecording.log() do
        conn =
          %{
            session_key: EncryptHeaderRecording.session_key()
          }
          |> Map.merge(input)

        {:ok, conn, encrypted_header} = Connection.encrypt_header(conn, input[:header])
        assert encrypted_header == output[:header]
        assert conn.send_i == output[:send_i]
        assert conn.send_j == output[:send_j]
      end
    end
  end

  describe "enqueue_packets/1" do
    test "can queue all packets in recording" do
      for %{input: input, output: output} <- DecryptPacketRecording.log() do
        conn =
          %Connection{
            session_key: DecryptPacketRecording.session_key()
          }
          |> Map.merge(input)
          |> Connection.enqueue_packets()

        assert not Enum.empty?(conn.packet_queue)

        [first | _] = conn.packet_queue

        assert output[:header] == <<first.size::big-size(16), first.opcode::little-size(32)>>
      end
    end
  end
end
