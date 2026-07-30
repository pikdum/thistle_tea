defmodule ThistleTea.Game.Network.Message.TaxiMessagesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.CmsgActivatetaxi
  alias ThistleTea.Game.Network.Message.CmsgActivatetaxiexpress
  alias ThistleTea.Game.Network.Message.CmsgTaxinodeStatusQuery
  alias ThistleTea.Game.Network.Message.CmsgTaxiqueryavailablenodes
  alias ThistleTea.Game.Network.Message.SmsgActivatetaxireply
  alias ThistleTea.Game.Network.Message.SmsgNewTaxiPath
  alias ThistleTea.Game.Network.Message.SmsgShowtaxinodes
  alias ThistleTea.Game.Network.Message.SmsgTaxinodeStatus

  describe "client decoders" do
    test "decodes taxi queries" do
      assert CmsgTaxinodeStatusQuery.from_binary(<<123::little-size(64)>>) ==
               %CmsgTaxinodeStatusQuery{guid: 123}

      assert CmsgTaxiqueryavailablenodes.from_binary(<<456::little-size(64)>>) ==
               %CmsgTaxiqueryavailablenodes{guid: 456}
    end

    test "decodes direct activation" do
      payload = <<123::little-size(64), 2::little-size(32), 4::little-size(32)>>

      assert CmsgActivatetaxi.from_binary(payload) ==
               %CmsgActivatetaxi{guid: 123, source_node: 2, destination_node: 4}
    end

    test "decodes express activation" do
      payload =
        <<123::little-size(64), 320::little-size(32), 3::little-size(32), 2::little-size(32), 4::little-size(32),
          6::little-size(32)>>

      assert CmsgActivatetaxiexpress.from_binary(payload) ==
               %CmsgActivatetaxiexpress{guid: 123, total_cost: 320, nodes: [2, 4, 6]}
    end
  end

  describe "server encoders" do
    test "encodes taxi node status" do
      assert SmsgTaxinodeStatus.to_binary(%SmsgTaxinodeStatus{guid: 123, known?: true}) ==
               <<123::little-size(64), 1>>

      assert SmsgTaxinodeStatus.to_binary(%SmsgTaxinodeStatus{guid: 123, known?: false}) ==
               <<123::little-size(64), 0>>
    end

    test "encodes the fixed Vanilla taxi mask" do
      mask = Enum.to_list(1..8)

      assert SmsgShowtaxinodes.to_binary(%SmsgShowtaxinodes{guid: 123, nearest_node: 2, nodes: mask}) ==
               <<1::little-size(32), 123::little-size(64), 2::little-size(32), 1::little-size(32), 2::little-size(32),
                 3::little-size(32), 4::little-size(32), 5::little-size(32), 6::little-size(32), 7::little-size(32),
                 8::little-size(32)>>
    end

    test "encodes activation replies and new-path notifications" do
      assert SmsgActivatetaxireply.to_binary(%SmsgActivatetaxireply{reply: 3}) == <<3::little-size(32)>>
      assert SmsgNewTaxiPath.to_binary(%SmsgNewTaxiPath{}) == <<>>
    end
  end
end
