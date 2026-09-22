defmodule ThistleTea.Game.Entity.Logic.ItemTransformationTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.ItemTransformation

  describe "prepare/3" do
    test "copies enchants and wear without copying charges, flags, identity, or other internal state" do
      original = Item.build(%ItemTemplate{entry: 1, max_durability: 100, spellcharges_1: -3}, 10, owner: 1)

      original =
        original
        |> Item.put_permanent_enchantment(41)
        |> Item.put_temporary_enchantment(323, 1000, 7, 2000, :token)
        |> Item.unlock()

      original = %{original | item: %{original.item | durability: 25}}
      replacement = Item.build(%ItemTemplate{entry: 2, max_durability: 80, spellcharges_1: -5}, 11, owner: 1)
      result = ItemTransformation.prepare(replacement, original, 1500)
      assert result.object == replacement.object
      assert Item.template(result) == Item.template(replacement)
      assert result.item.durability == 20
      assert result.item.flags == 0
      assert Item.spell_charge(result, 1) == -5
      assert Item.active_enchantments(result, 1500) == [{0, 41}, {1, 323}]
      assert Item.temporary_enchantment(result) == %{id: 323, charges: 7, expires_at: 2000, token: :token}
      assert Bitwise.band(Bitwise.bsr(result.item.enchantment, 128), 0xFFFFFFFF) == 500
    end

    test "preserves broken and undamaged states and rounds partial losses down with a minimum of one" do
      for {old_maximum, current, maximum, expected} <- [
            {100, 0, 80, 0},
            {100, 100, 80, 80},
            {100, 99, 20, 19},
            {100, 67, 20, 14},
            {0, 0, 20, 20},
            {100, 50, 0, 0}
          ] do
        original = Item.build(%ItemTemplate{entry: 1, max_durability: old_maximum}, 10)
        original = %{original | item: %{original.item | durability: current}}
        replacement = Item.build(%ItemTemplate{entry: 2, max_durability: maximum}, 11)
        assert ItemTransformation.prepare(replacement, original, 0).item.durability == expected
      end
    end

    test "drops expired temporary enchants while retaining permanent enchants" do
      original =
        %ItemTemplate{entry: 1}
        |> Item.build(10)
        |> Item.put_permanent_enchantment(41)
        |> Item.put_temporary_enchantment(323, 1000, 7, 2000, :token)

      result = ItemTransformation.prepare(Item.build(%ItemTemplate{entry: 2}, 11), original, 2000)
      assert Item.active_enchantments(result, 2000) == [{0, 41}]
      assert Item.temporary_enchantment(result) == nil
    end
  end
end
