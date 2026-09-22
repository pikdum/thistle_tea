defmodule ThistleTea.Game.World.Loader.SpellItemTransformationDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "loads weapon transformations and both festive mug forms with destination entries" do
      for {spell_id, item_id} <- [
            {21_180, 17_223},
            {21_181, 17_074},
            {23_041, 18_609},
            {23_042, 18_608},
            {25_851, 21_174},
            {25_855, 21_171}
          ] do
        spell = SpellLoader.load(spell_id)

        assert %{misc_value: ^item_id, semantic: %Semantics.Inventory{kind: :summon_change_item}} =
                 Enum.find(spell.effects, &(&1.type == :summon_change_item))
      end
    end
  end
end
