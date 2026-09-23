defmodule ThistleTea.Game.Network.Message.MsgCorpseQueryResponseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.MsgCorpseQueryResponse

  describe "to_binary/1" do
    test "encodes the displayed map separately from the actual corpse map" do
      message = %MsgCorpseQueryResponse{map: 0, position: {1.0, 2.0, 3.0}, corpse_map: 36}

      assert MsgCorpseQueryResponse.to_binary(message) ==
               <<1, 0::little-signed-size(32), 1.0::little-float-size(32), 2.0::little-float-size(32),
                 3.0::little-float-size(32), 36::little-size(32)>>
    end

    test "retains open-world and missing-corpse responses" do
      message = %MsgCorpseQueryResponse{map: 1, position: {1.0, 2.0, 3.0}}
      assert binary_part(MsgCorpseQueryResponse.to_binary(message), 17, 4) == <<1::little-size(32)>>
      assert MsgCorpseQueryResponse.to_binary(%MsgCorpseQueryResponse{}) == <<0>>
    end
  end
end
