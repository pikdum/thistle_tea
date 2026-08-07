defmodule ThistleTea.Game.Entity.Data.Component.PlayerUpdateFieldsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player

  describe "to_list/2" do
    test "encodes the vanilla bank storage field regions" do
      fields =
        %Player{
          bank1: 1,
          bank24: 24,
          bank_bag1: 25,
          bank_bag6: 30,
          buyback1: 31,
          buyback12: 42,
          farsight: 43
        }
        |> Player.to_list()
        |> Map.new(fn {field, value, metadata} -> {field, {value, metadata}} end)

      assert fields.bank1 == {1, {0x0234, 2, :guid}}
      assert fields.bank24 == {24, {0x0262, 2, :guid}}
      assert fields.bank_bag1 == {25, {0x0264, 2, :guid}}
      assert fields.bank_bag6 == {30, {0x026E, 2, :guid}}
      assert fields.buyback1 == {31, {0x0270, 2, :guid}}
      assert fields.buyback12 == {42, {0x0286, 2, :guid}}
      assert fields.farsight == {43, {0x02C8, 2, :guid}}
    end

    test "packs bank bag slots into byte 2" do
      player = %Player{facial_hair: 1, bank_bag_slots: 6, rest_state: 3}

      assert {:bytes_2, <<1, 0, 6, 3>>, {0x00C2, 1, :bytes}} in Player.to_list(player)
    end
  end
end
