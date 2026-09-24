defmodule ThistleTea.Game.World.Loader.SpellPartyTargetDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "party-wide class buffs resolve around the selected player" do
      for spell_id <- [21_562, 21_849, 23_028, 27_681, 27_683] do
        spell = SpellLoader.load(spell_id)

        assert Enum.all?(spell.effects, &(&1.implicit_target_a == :party_around_target))

        assert SpellTarget.target_query(spell, Target.unit(7)) ==
                 {:target_party_aoe, 7, 100.0}
      end
    end

    test "imp Fire Shield retains its party-only target" do
      for spell_id <- [2947, 8316, 8317, 11_770, 11_771] do
        spell = SpellLoader.load(spell_id)

        assert hd(spell.effects).implicit_target_a == :party_member
        assert SpellTarget.target_query(spell, Target.unit(7)) == {:party_unit, 7}
      end
    end
  end
end
