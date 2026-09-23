defmodule ThistleTea.Game.Network.Message.GuildTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guild.Group
  alias ThistleTea.Game.Guild.Rank
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Message.SmsgGuildRoster.Entry
  alias ThistleTea.Game.Network.Opcodes

  describe "to_binary/1" do
    test "encodes the Vanilla guild query and roster layouts" do
      guild = %Group{
        id: 7,
        name: "Fellowship",
        leader: 1,
        members: %{},
        ranks: [%Rank{name: "Master", rights: 0xFF1FF}, %Rank{name: "Member", rights: 0x43}],
        motd: "Welcome",
        info: "Friends"
      }

      query = Message.SmsgGuildQueryResponse.to_binary(%Message.SmsgGuildQueryResponse{guild: guild})

      assert query ==
               <<7::little-size(32)>> <>
                 "Fellowship" <>
                 <<0>> <>
                 "Master" <>
                 <<0>> <>
                 "Member" <>
                 :binary.copy(<<0>>, 9) <> <<0::size(160)>>

      entries = [
        %Entry{guid: 1, name: "Founder", rank: 0, level: 60, class: 1, area: 12, online?: true},
        %Entry{guid: 2, name: "Member", rank: 1, level: 20, class: 8, area: 33, online?: false, offline_days: 1.5}
      ]

      roster = Message.SmsgGuildRoster.to_binary(%Message.SmsgGuildRoster{guild: guild, entries: entries})

      assert roster ==
               <<2::little-size(32)>> <>
                 "Welcome" <>
                 <<0>> <>
                 "Friends" <>
                 <<0, 2::little-size(32), 0xFF1FF::little-size(32), 0x43::little-size(32), 1::little-size(64), 1>> <>
                 "Founder" <>
                 <<0, 0::little-size(32), 60, 1, 12::little-size(32)>> <>
                 <<0, 0>> <>
                 <<2::little-size(64), 0>> <>
                 "Member" <>
                 <<0, 1::little-size(32), 20, 8, 33::little-size(32), 1.5::little-float-size(32), 0, 0>>
    end

    test "encodes invitation, events, and command results" do
      assert Message.SmsgGuildInvite.to_binary(%Message.SmsgGuildInvite{
               inviter_name: "Founder",
               guild_name: "Fellowship"
             }) == "Founder" <> <<0>> <> "Fellowship" <> <<0>>

      assert Message.SmsgGuildEvent.to_binary(%Message.SmsgGuildEvent{event: :joined, descriptions: ["Member"]}) ==
               <<3, 1>> <> "Member" <> <<0>>

      assert Message.SmsgGuildCommandResult.to_binary(%Message.SmsgGuildCommandResult{
               command: :invite,
               name: "Enemy",
               result: :wrong_faction
             }) == <<1::little-size(32)>> <> "Enemy" <> <<0, 12::little-size(32)>>
    end
  end

  describe "from_binary/1" do
    test "registers and parses core guild requests" do
      assert Dispatch.implemented?(Opcodes.get(:CMSG_GUILD_QUERY))
      assert Dispatch.implemented?(Opcodes.get(:CMSG_GUILD_CREATE))
      assert %Message.CmsgGuildQuery{guild_id: 7} = Message.CmsgGuildQuery.from_binary(<<7::little-size(32)>>)

      assert %Message.CmsgGuildCreate{name: "Fellowship"} =
               Message.CmsgGuildCreate.from_binary("Fellowship" <> <<0>>)

      assert %Message.CmsgGuildInvite{name: "Member"} = Message.CmsgGuildInvite.from_binary("Member" <> <<0>>)
      assert %Message.CmsgGuildAccept{} = Message.CmsgGuildAccept.from_binary(<<>>)
      assert Dispatch.implemented?(Opcodes.get(:CMSG_GUILD_RANK))
      assert Dispatch.implemented?(Opcodes.get(:CMSG_GUILD_ADD_RANK))
      assert Dispatch.implemented?(Opcodes.get(:CMSG_GUILD_DEL_RANK))

      assert %Message.CmsgGuildRank{rank_id: 4, rights: 0x43, name: "Initiate"} =
               Message.CmsgGuildRank.from_binary(<<4::little-size(32), 0x43::little-size(32)>> <> "Initiate" <> <<0>>)

      assert %Message.CmsgGuildAddRank{name: "Scout"} = Message.CmsgGuildAddRank.from_binary("Scout" <> <<0>>)
      assert %Message.CmsgGuildDelRank{} = Message.CmsgGuildDelRank.from_binary(<<>>)
    end
  end
end
