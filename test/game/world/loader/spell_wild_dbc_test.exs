defmodule ThistleTea.Game.World.Loader.SpellWildDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  @moduletag :dbc_db

  describe "load/1" do
    test "every wild summon includes its caster execution target" do
      ids = DBC.all(from(s in DBC.Spell, where: s.effect_0 == 41 or s.effect_1 == 41 or s.effect_2 == 41, select: s.id))
      saved = Enum.flat_map(ids, &:ets.take(SpellEffectOverride, {:mods, &1}))
      on_exit(fn -> :ets.insert(SpellEffectOverride, saved) end)

      caster = %Character{
        object: %Object{guid: 7},
        internal: %Internal{world: WorldRef.open(998)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      effects =
        Enum.flat_map(ids, fn id ->
          spell = SpellLoader.load(id)
          assert 7 in SpellTargetResolver.resolve(caster, spell, Target.none())
          Enum.filter(spell.effects, &(&1.type == :summon_wild))
        end)

      assert length(effects) == 372
      assert Enum.all?(effects, &match?(%{semantic: %Semantics.SummonControl{kind: :summon_wild}}, &1))
    end
  end
end
