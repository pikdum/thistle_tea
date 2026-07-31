defmodule ThistleTea.Game.Network.Message.ReputationMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgSetFactionAtwar
  alias ThistleTea.Game.Network.Message.CmsgSetFactionInactive
  alias ThistleTea.Game.Network.Message.CmsgSetWatchedFaction
  alias ThistleTea.Game.Network.Message.SmsgInitializeFactions
  alias ThistleTea.Game.Network.Message.SmsgSetFactionAtwar
  alias ThistleTea.Game.Network.Message.SmsgSetFactionStanding
  alias ThistleTea.Game.Network.Message.SmsgSetFactionVisible

  describe "SMSG_INITIALIZE_FACTIONS" do
    test "encodes all 64 flag and signed-standing slots" do
      factions = [{0x03, -6_500}, {0x11, 3_100}] ++ List.duplicate({0, 0}, 62)
      binary = SmsgInitializeFactions.to_binary(%SmsgInitializeFactions{factions: factions})

      assert <<64::little-size(32), 0x03, -6_500::little-signed-size(32), 0x11, 3_100::little-signed-size(32),
               rest::binary>> = binary

      assert byte_size(rest) == 62 * 5
    end
  end

  describe "SMSG_SET_FACTION_STANDING" do
    test "encodes reputation-list indices and signed offsets" do
      binary =
        SmsgSetFactionStanding.to_binary(%SmsgSetFactionStanding{
          standings: [{19, 250}, {0, -125}]
        })

      assert binary ==
               <<2::little-size(32), 19::little-size(32), 250::little-signed-size(32), 0::little-size(32),
                 -125::little-signed-size(32)>>
    end
  end

  describe "single-faction server messages" do
    test "encode visibility and at-war changes" do
      assert SmsgSetFactionVisible.to_binary(%SmsgSetFactionVisible{index: 19}) ==
               <<19::little-size(32)>>

      assert SmsgSetFactionAtwar.to_binary(%SmsgSetFactionAtwar{index: 19, enabled: true}) ==
               <<19::little-size(32), 0x02>>

      assert SmsgSetFactionAtwar.to_binary(%SmsgSetFactionAtwar{index: 19, enabled: false}) ==
               <<19::little-size(32), 0>>
    end
  end

  describe "client message parsing" do
    test "parses at-war, inactive, and watched-faction controls" do
      assert %CmsgSetFactionAtwar{index: 19, flags: 2} =
               CmsgSetFactionAtwar.from_binary(<<19::little-size(32), 2>>)

      assert %CmsgSetFactionInactive{index: 19, inactive: 1} =
               CmsgSetFactionInactive.from_binary(<<19::little-size(32), 1>>)

      assert %CmsgSetWatchedFaction{index: -1} =
               CmsgSetWatchedFaction.from_binary(<<-1::little-signed-size(32)>>)
    end
  end
end
