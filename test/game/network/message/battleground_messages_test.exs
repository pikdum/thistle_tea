defmodule ThistleTea.Game.Network.Message.BattlegroundMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message

  describe "client decoders" do
    test "decodes battlemaster queue and port requests" do
      assert %Message.CmsgBattlemasterJoin{
               guid: 42,
               map: 489,
               instance_id: 7,
               join_as_group: true
             } =
               Message.CmsgBattlemasterJoin.from_binary(
                 <<42::little-size(64), 489::little-size(32), 7::little-size(32), 1>>
               )

      assert %Message.CmsgBattlefieldPort{map: 489, action: 1} =
               Message.CmsgBattlefieldPort.from_binary(<<489::little-size(32), 1>>)
    end
  end

  describe "SMSG_BATTLEFIELD_STATUS" do
    test "uses the state-dependent VMangos wire layout" do
      assert Message.SmsgBattlefieldStatus.to_binary(%Message.SmsgBattlefieldStatus{}) ==
               <<0::little-size(32), 0::little-size(32)>>

      wait_join = %Message.SmsgBattlefieldStatus{
        map: 489,
        bracket: 5,
        client_instance_id: 9,
        status: :wait_join,
        time_one_ms: 80_000
      }

      assert Message.SmsgBattlefieldStatus.to_binary(wait_join) ==
               <<0::little-size(32), 489::little-size(32), 5, 9::little-size(32), 2::little-size(32),
                 80_000::little-size(32)>>

      in_progress = %{wait_join | status: :in_progress, time_one_ms: 120_000, time_two_ms: 3_000}

      assert Message.SmsgBattlefieldStatus.to_binary(in_progress) ==
               <<0::little-size(32), 489::little-size(32), 5, 9::little-size(32), 3::little-size(32),
                 120_000::little-size(32), 3_000::little-size(32)>>
    end
  end

  describe "MSG_PVP_LOG_DATA" do
    test "encodes the WSG capture and return fields" do
      message = %Message.MsgPvpLogData{
        ended?: true,
        winner: :alliance,
        players: [
          %{
            guid: 42,
            rank: 4,
            killing_blows: 1,
            honorable_kills: 2,
            deaths: 3,
            bonus_honor: 4,
            fields: [5, 6]
          }
        ]
      }

      assert Message.MsgPvpLogData.to_binary(message) ==
               <<1, 1, 1::little-size(32), 42::little-size(64), 4::little-size(32), 1::little-size(32),
                 2::little-size(32), 3::little-size(32), 4::little-size(32), 2::little-size(32), 5::little-size(32),
                 6::little-size(32)>>
    end
  end
end
