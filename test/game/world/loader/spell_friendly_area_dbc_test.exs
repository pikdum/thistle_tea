defmodule ThistleTea.Game.World.Loader.SpellFriendlyAreaDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "healing wards select friends without treating their source location as hostile" do
      for id <- [5016, 5607, 6275, 11_900] do
        spell = SpellLoader.load(id)
        refute Spell.harmful?(spell)
        assert SpellTarget.area_targeted?(spell)
        assert SpellTarget.target_query(spell, Target.unit(123)) == {:caster_friendly_aoe, 10.0}
      end
    end

    test "a caster source retains the explicit enemy area selector" do
      for id <- [1449, 22_703] do
        spell = SpellLoader.load(id)
        assert Spell.harmful?(spell)
        assert SpellTarget.target_query(spell, Target.none()) == {:caster_aoe, 10.0}
      end
    end
  end
end
