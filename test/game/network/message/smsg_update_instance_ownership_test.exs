defmodule ThistleTea.Game.Network.Message.SmsgUpdateInstanceOwnershipTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message.SmsgUpdateInstanceOwnership

  describe "to_binary/1" do
    test "encodes raid ownership" do
      assert SmsgUpdateInstanceOwnership.to_binary(%SmsgUpdateInstanceOwnership{}) == <<0::little-size(32)>>

      assert SmsgUpdateInstanceOwnership.to_binary(%SmsgUpdateInstanceOwnership{
               player_is_saved_to_a_raid: true
             }) == <<1::little-size(32)>>
    end
  end
end
