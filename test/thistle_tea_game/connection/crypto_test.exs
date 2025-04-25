defmodule ThistleTeaGame.Connection.CryptoTest do
  use ExUnit.Case

  alias ThistleTeaGame.Connection
  alias ThistleTeaGame.Connection.Crypto

  alias ThistleTea.Test.EncryptHeaderRecording
  alias ThistleTea.Test.DecryptHeaderRecording

  describe "decrypt_header/1" do
    test "returns an error when there is no session key" do
      conn = %Connection{}
      assert {:error, ^conn, :no_session_key} = Crypto.decrypt_header(conn)
    end

    test "returns an error when there is not enough data" do
      conn = %Connection{session_key: DecryptHeaderRecording.session_key()}
      assert {:error, ^conn, :not_enough_data} = Crypto.decrypt_header(conn)
    end

    test "can decrypt all headers in recording" do
      for %{input: input, output: output} <- DecryptHeaderRecording.log() do
        conn =
          %Connection{
            session_key: DecryptHeaderRecording.session_key()
          }
          |> Map.merge(input)

        {:ok, conn, decrypted_header} = Crypto.decrypt_header(conn)
        assert decrypted_header == output[:header]
        assert conn.recv_i == output[:recv_i]
        assert conn.recv_j == output[:recv_j]
      end
    end
  end

  describe "encrypt_header/2" do
    test "can encrypt all headers in recording" do
      for %{input: input, output: output} <- EncryptHeaderRecording.log() do
        conn =
          %Connection{
            session_key: EncryptHeaderRecording.session_key()
          }
          |> Map.merge(input)

        {:ok, conn, encrypted_header} = Crypto.encrypt_header(conn, input[:header])
        assert encrypted_header == output[:header]
        assert conn.send_i == output[:send_i]
        assert conn.send_j == output[:send_j]
      end
    end
  end

  describe "verify_proof/3" do
    test "can verify proof" do
    end
  end
end
