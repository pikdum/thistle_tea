defmodule ThistleTea.Game.Entity.Logic.ConditionalTriggersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:entities]

  describe "receive/4" do
    test "boomerang rolls disarm and stun independently without changing its damage", context do
      {damaged, events} = SpellEffect.receive(context.target, context.cast, boomerang(), 0)
      assert damaged.unit.health == 90
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 10}, &1))
      assert damaged.unit.auras == []
      assert [disarm, stun] = Enum.filter(events, &is_struct(&1, RandomChoice))
      assert RandomChoice.total_weight(disarm) == 31
      assert RandomChoice.total_weight(stun) == 11

      outcomes =
        for disarm_roll <- 1..31, stun_roll <- 1..11 do
          selected = RandomChoice.select(disarm, disarm_roll) ++ RandomChoice.select(stun, stun_roll)

          for trigger <- selected do
            assert %Effects.TriggerSpell{source_guid: 1, source_level: 60, target_guid: 2, hit_context: hit} = trigger
            assert hit.cast_item_guid == 42
          end

          Enum.map(selected, & &1.spell_id)
        end

      assert Enum.frequencies(outcomes) == %{[] => 300, [15_752] => 10, [15_753] => 30, [15_752, 15_753] => 1}
    end

    test "a lethal or immune hit cannot roll optional triggers", context do
      dead = %{context.target | unit: %{context.target.unit | health: 0}}
      {^dead, []} = SpellEffect.receive(dead, context.cast, boomerang(), 0)
      fragile = %{context.target | unit: %{context.target.unit | health: 5}}
      {killed, events} = SpellEffect.receive(fragile, context.cast, boomerang(), 0)
      assert killed.unit.health == 0
      refute Enum.any?(events, &is_struct(&1, RandomChoice))

      holder = %Holder{spell: %Spell{id: 642}, auras: [%AuraData{type: :school_immunity, misc_value: 127}]}
      immune = %{context.target | unit: %{context.target.unit | auras: [holder]}}
      {immune, events} = SpellEffect.receive(immune, context.cast, boomerang(), 0)
      assert immune.unit.health == 100
      refute Enum.any?(events, &is_struct(&1, RandomChoice))
      assert Enum.any?(events, &match?(%Effects.SpellLogMiss{reason: :immune}, &1))
    end

    test "food applies normally while poison is an optional self trigger", context do
      spell = %Spell{
        id: 6410,
        script_name: "spell_scorpid_surprise",
        duration_ms: 21_000,
        effects: [
          %Effect{
            index: 0,
            type: :apply_aura,
            aura: :mod_regen,
            base_points: 69,
            base_dice: 1,
            die_sides: 1,
            implicit_target_a: :caster
          },
          %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 6411, implicit_target_a: :caster}
        ]
      }

      cast = %{context.cast | caster_guid: 2, target_guid: 2}
      {eating, events} = SpellEffect.receive(context.target, cast, spell, 0)
      assert Aura.has_spell?(eating, 6410)
      assert Aura.flat_amount(eating, :mod_regen) == 70
      assert [choice] = Enum.filter(events, &is_struct(&1, RandomChoice))
      assert RandomChoice.total_weight(choice) == 11
      assert [%Effects.TriggerSpell{source_guid: 2, target_guid: 2, spell_id: 6411}] = RandomChoice.select(choice, 1)
      for roll <- 2..11, do: assert(RandomChoice.select(choice, roll) == [])
      refute Aura.has_spell?(eating, 6411)
    end

    test "effect targeting and masks are applied before optional rolls", context do
      spell = boomerang()
      caster = %{context.target | object: %Object{guid: 1}}
      assert {^caster, []} = SpellEffect.receive(caster, %{context.cast | target_role: :caster}, spell, 0)

      {_, events} = SpellEffect.receive(context.target, %{context.cast | effect_indices: [2]}, spell, 0)
      assert [%RandomChoice{} = choice] = events
      assert [%Effects.TriggerSpell{spell_id: 15_753}] = RandomChoice.select(choice, 1)
    end

    test "ordinary trigger effects stay unconditional", context do
      spell = %{boomerang() | script_name: nil}
      {_, events} = SpellEffect.receive(context.target, context.cast, spell, 0)
      refute Enum.any?(events, &is_struct(&1, RandomChoice))
      assert Enum.map(Enum.filter(events, &is_struct(&1, Effects.TriggerSpell)), & &1.spell_id) == [15_752, 15_753]
    end
  end

  defp boomerang do
    %Spell{
      id: 15_712,
      school: :arcane,
      script_name: "spell_linkens_boomerang",
      effects: [
        %Effect{
          index: 0,
          type: :school_damage,
          base_points: 9,
          base_dice: 1,
          die_sides: 1,
          implicit_target_a: :target_enemy
        },
        %Effect{index: 1, type: :trigger_spell, trigger_spell_id: 15_752, implicit_target_a: :target_enemy},
        %Effect{index: 2, type: :trigger_spell, trigger_spell_id: 15_753, implicit_target_a: :target_enemy}
      ]
    }
  end

  defp entities(_context) do
    %{
      target: %Character{
        object: %Object{guid: 2},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{}
      },
      cast: %CastContext{caster_guid: 1, caster_level: 60, target_guid: 2, cast_item_guid: 42}
    }
  end
end
