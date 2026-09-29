defmodule ThistleTea.Game.World.Loader.SpellMiniPetDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  @moduletag :dbc_db

  describe "load/1" do
    test "all critter summons execute on the caster without a selected unit" do
      ids = DBC.all(from(s in Spell, where: s.effect_0 == 97, select: s.id))
      assert length(ids) == 100
      caster = %Character{object: %Object{guid: 7}}

      for id <- ids do
        spell = SpellLoader.load(id)

        assert Enum.any?(
                 spell.effects,
                 &match?(%{type: :summon_mini_pet, semantic: %Semantics.SummonControl{kind: :summon_mini_pet}}, &1)
               )

        assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [7]
      end
    end
  end
end
