defmodule ThistleTeaGame.ConnectionTest do
  use ExUnit.Case

  alias ThistleTea.Test.DecryptPacketRecording
  alias ThistleTeaGame.Connection

  describe "decrypt_header/1" do
    test "returns an error when there is not enough data" do
      conn = %Connection{}
      assert {:error, ^conn, :not_enough_data} = Connection.decrypt_header(conn)
    end

    test "can decrypt a single packet header" do
      conn = %Connection{
        packet_stream: <<181, 178, 115, 237, 121, 115>>,
        session_key:
          <<181, 249, 246, 122, 140, 250, 240, 250, 14, 174, 36, 59, 11, 32, 187, 169, 4, 251,
            223, 184, 15, 34, 63, 49, 123, 54, 106, 148, 141, 130, 97, 239, 141, 109, 65, 180, 50,
            144, 153, 201>>,
        recv_i: 0,
        recv_j: 0
      }

      {:ok, conn, decrypted_header} = Connection.decrypt_header(conn)

      assert conn.recv_i == 6
      assert conn.recv_j == 115
      assert decrypted_header == <<0, 4, 55, 0, 0, 0>>
    end

    test "can decrypt all headers in recording" do
      conn = %Connection{
        session_key: DecryptPacketRecording.session_key()
      }

      DecryptPacketRecording.log()
      |> Enum.reduce(conn, fn %{input: input, output: output}, conn ->
        conn = Map.merge(conn, input)
        {:ok, conn, decrypted_header} = Connection.decrypt_header(conn)
        assert decrypted_header == output[:header]
        assert conn.recv_i == output[:recv_i]
        assert conn.recv_j == output[:recv_j]
        conn
      end)
    end
  end

  describe "decrypt_packets/1" do
    test "can decrypt a single packet" do
      [%{input: input} | _] = DecryptPacketRecording.log()

      conn =
        %Connection{
          session_key: DecryptPacketRecording.session_key()
        }
        |> Map.merge(input)
        |> Connection.decrypt_packets()

      assert %{
               size: 4,
               opcode: 55,
               payload: <<>>
             } in conn.packet_queue
    end

    test "can decrypt all packets in recording" do
      conn = %Connection{
        session_key: DecryptPacketRecording.session_key()
      }

      DecryptPacketRecording.log()
      |> Enum.reduce(conn, fn %{input: input, output: output}, conn ->
        conn =
          conn
          |> Map.merge(input)
          |> Map.put(:packet_queue, [])
          |> Connection.decrypt_packets()

        assert not Enum.empty?(conn.packet_queue)

        [first | _] = conn.packet_queue

        assert output[:header] == <<first.size::big-size(16), first.opcode::little-size(32)>>

        conn
      end)
    end
  end
end
