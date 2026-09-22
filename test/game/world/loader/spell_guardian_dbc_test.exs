defmodule ThistleTea.Game.World.Loader.SpellGuardianDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  describe "load/1" do
    test "guardian summons include the caster execution target" do
      ids = DBC.all(from(s in Spell, where: s.effect_0 == 42 or s.effect_1 == 42 or s.effect_2 == 42, select: s.id))

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
          Enum.filter(spell.effects, &(&1.type == :summon_guardian))
        end)

      assert length(effects) == 211
      assert Enum.all?(effects, &match?(%{semantic: %Semantics.SummonControl{kind: :summon_guardian}}, &1))
    end

    test "engineering trinket wrappers retain their item through triggered delivery" do
      caster = %Character{
        object: %Object{guid: 7},
        unit: %Unit{level: 60, health: 100},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(998)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      for {wrapper, summon} <- [{23_074, 19_804}, {23_075, 12_749}, {23_076, 4073}, {23_133, 13_166}] do
        spell = SpellLoader.load(wrapper)
        context = %{CastContext.from_caster(caster, spell, 7) | cast_item_guid: 55}
        {_, events} = SpellEffect.receive(caster, context, spell, 1000)
        assert [%Effects.TriggerSpell{spell_id: ^summon, cast_item_guid: 55} = trigger] = events
        resolved = Spells.resolve(caster, trigger)

        assert %Effects.DeliverSpell{cast_context: %{cast_item_guid: 55, triggered?: true}} =
                 Enum.find(resolved, &is_struct(&1, Effects.DeliverSpell))

        assert {_, []} = SpellEffect.receive(caster, %{context | cast_item_guid: nil}, spell, 1000)
      end
    end
  end
end
