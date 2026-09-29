defmodule ThistleTea.Game.World.Loader.SpellGuardianDbcTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.PetSpellModifiers
  alias ThistleTea.Game.Core.Profession.Engineering
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellEffectOverride
  alias ThistleTea.Game.World.Spell.SpellTargetResolver

  @moduletag :dbc_db

  describe "load/1" do
    test "engineering guardian passives derive health and damage from DBC" do
      for {entry, health, damage} <- [{2678, 300, 50}, {8615, 500, 90}, {12_473, 700, 115}] do
        spell = entry |> Engineering.guardian_passive() |> SpellLoader.load()

        guardian = %Mob{
          object: %Object{guid: 7, entry: entry},
          unit: %Unit{
            stat_model: :creature,
            level: 60,
            health: 1,
            max_health: 1,
            base_health: 0,
            base_min_damage: 10.0,
            base_max_damage: 20.0,
            auras: []
          },
          internal: %Internal{pet: %Pet{owner_guid: 1, kind: :guardian}}
        }

        buffed = PetSpellModifiers.apply_passive(guardian, spell, 0)
        assert buffed.unit.max_health == health
        assert buffed.unit.min_damage == 10 + damage
        assert buffed.unit.max_damage == 20 + damage
      end

      assert Engineering.guardian_passive(416) == nil
    end

    test "guardian summons include the caster execution target" do
      ids = DBC.all(from(s in DBC.Spell, where: s.effect_0 == 42 or s.effect_1 == 42 or s.effect_2 == 42, select: s.id))

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
      ids = [23_074, 19_804, 23_075, 12_749, 23_076, 4073, 23_133, 13_166]
      saved_mods = Enum.flat_map(ids, &:ets.take(SpellEffectOverride, {:mods, &1}))
      saved_spells = Enum.flat_map(ids, &:ets.take(SpellLoader, {:spell, &1}))

      on_exit(fn ->
        Enum.each(ids, &:ets.delete(SpellLoader, {:spell, &1}))
        :ets.insert(SpellEffectOverride, saved_mods)
        :ets.insert(SpellLoader, saved_spells)
      end)

      caster = %Character{
        object: %Object{guid: 7},
        unit: %Unit{level: 60, health: 100},
        player: %Player{},
        internal: %Internal{world: WorldRef.open(998)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      for {wrapper, summon} <- [{23_074, 19_804}, {23_075, 12_749}, {23_076, 4073}, {23_133, 13_166}] do
        spell = SpellLoader.load(wrapper)
        started = caster |> Casting.start(spell, Target.self(7), 1_000, 55) |> Casting.complete(1_000)

        assert Enum.any?(
                 started.internal.events,
                 &match?(%Effects.TriggerSpell{spell_id: ^summon, cast_item_guid: 55}, &1)
               )

        context = %{CastContext.from_caster(caster, spell, 7) | cast_item_guid: 55}
        {_, events} = SpellEffect.receive(caster, context, spell, 1000)
        assert [%Effects.TriggerSpell{spell_id: ^summon, cast_item_guid: 55} = trigger] = events
        resolved = Spells.resolve(caster, trigger)

        assert %Effects.DeliverSpell{cast_context: %{cast_item_guid: 55, triggered?: true}} =
                 delivery =
                 Enum.find(resolved, &is_struct(&1, Effects.DeliverSpell))

        {_, summons} = SpellEffect.receive(caster, delivery.cast_context, delivery.spell, 1_000)

        if wrapper == 23_133,
          do: assert([%Effects.SummonTotem{entry: 8836}] = summons),
          else: assert([%Effects.SummonGuardians{cast_item_guid: 55}] = summons)

        assert {_, []} = SpellEffect.receive(caster, %{context | cast_item_guid: nil}, spell, 1000)
      end
    end
  end
end
