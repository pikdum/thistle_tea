defmodule ThistleTea.Game.Network.Connection.CryptoTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Connection.Crypto

  describe "encrypt_header/2" do
    test "authentication rejection stays unencrypted before a session key exists" do
      connection = %Connection{}
      header = <<0, 3, 238, 1>>
      assert {:ok, ^connection, ^header} = Crypto.encrypt_header(connection, header)
      assert {:error, ^connection, :no_session_key} = Crypto.decrypt_header(connection)
    end

    test "authenticated headers retain rolling encryption" do
      connection = %Connection{session_key: <<1, 2, 3>>}
      assert {:ok, updated, <<1, 2, 239, 239>>} = Crypto.encrypt_header(connection, <<0, 3, 238, 1>>)
      assert updated.send_i == 1
      assert updated.send_j == 239
      assert updated.session_key == connection.session_key
    end
  end
end
