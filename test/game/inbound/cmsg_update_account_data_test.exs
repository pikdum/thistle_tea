defmodule ThistleTea.Game.Inbound.CmsgUpdateAccountDataTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Player.AccountData
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgRequestAccountData
  alias ThistleTea.Game.Inbound.CmsgUpdateAccountData
  alias ThistleTea.Game.Inbound.Dispatch
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message.SmsgAccountDataMd5
  alias ThistleTea.Game.Network.Message.SmsgUpdateAccountData
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World.Entity.Player.AccountCaches
  alias ThistleTea.Test.Unique

  @bindings "bind W MOVEFORWARD\n"

  describe "from_binary/1" do
    test "inflates the upload, with or without its trailing checksum" do
      compressed = :zlib.compress(@bindings)
      unchecked = binary_part(compressed, 0, byte_size(compressed) - 4)

      for payload <- [compressed, unchecked] do
        assert %CmsgUpdateAccountData{type: 2, data: @bindings} = decode(2, byte_size(@bindings), payload)
      end
    end

    test "reads a zero size as an erase and rejects data that does not inflate" do
      assert %CmsgUpdateAccountData{type: 4, data: ""} = decode(4, 0, <<>>)
      assert %CmsgUpdateAccountData{data: nil} = decode(4, 10, "not zlib")
      assert %CmsgUpdateAccountData{data: nil} = decode(4, 99, :zlib.compress(@bindings))
    end
  end

  describe "handle/2" do
    test "keeps account caches across characters and character caches per character" do
      account_id = Unique.integer()
      warrior = %{account: %{id: account_id}, character: %{object: %{guid: Unique.integer()}}}
      mage = %{warrior | character: %{object: %{guid: Unique.integer()}}}

      Inbound.handle(decode(2, byte_size(@bindings), :zlib.compress(@bindings)), warrior)
      Inbound.handle(decode(3, byte_size(@bindings), :zlib.compress(@bindings)), warrior)

      assert %SmsgAccountDataMd5{digests: digests} = AccountCaches.digests(account_id, mage.character.object.guid)
      assert Enum.at(digests, 2) == AccountData.digest(@bindings)
      assert Enum.at(digests, 3) == <<0::128>>

      Inbound.handle(%CmsgRequestAccountData{type: 3}, warrior)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgUpdateAccountData{type: 3, data: @bindings}}}
    end

    test "files caches uploaded after logout under the last character" do
      account_id = Unique.integer()
      guid = Unique.integer()
      state = %ConnectionState{account: %{id: account_id}, character_guid: guid}

      assert Inbound.handle(decode(7, 4, :zlib.compress("chat")), state) == state
      assert %SmsgAccountDataMd5{digests: digests} = AccountCaches.digests(account_id, guid)
      assert Enum.at(digests, 7) == AccountData.digest("chat")

      Inbound.handle(decode(7, 0, <<>>), state)
      assert %SmsgAccountDataMd5{digests: digests} = AccountCaches.digests(account_id, guid)
      assert Enum.at(digests, 7) == <<0::128>>
    end
  end

  describe "SmsgUpdateAccountData.to_binary/1" do
    test "sends the size and compressed text, or a bare zero size when empty" do
      payload = SmsgUpdateAccountData.to_binary(%SmsgUpdateAccountData{type: 4, data: @bindings})
      size = byte_size(@bindings)
      assert <<4::little-32, ^size::little-32, compressed::binary>> = payload
      assert :zlib.uncompress(compressed) == @bindings

      assert SmsgUpdateAccountData.to_binary(%SmsgUpdateAccountData{type: 4}) == <<4::little-32, 0::little-32>>
    end
  end

  defp decode(type, size, compressed) do
    Dispatch.to_message(%Packet{
      opcode: Opcodes.get(:CMSG_UPDATE_ACCOUNT_DATA),
      payload: <<type::little-32, size::little-32, compressed::binary>>
    })
  end
end
