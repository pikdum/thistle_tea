defmodule ThistleTea.Game.Entity.Logic.BinarySpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  describe "binary?/1" do
    test "classifies magical control effects and preserves the classification after filtering" do
      for aura <- [
            :mod_decrease_speed,
            :mod_fear,
            :mod_stun,
            :mod_pacify,
            :mod_root,
            :mod_silence,
            :mod_disarm,
            :mod_resistance,
            :mod_damage_taken
          ] do
        spell = %{frostbolt() | effects: [%Effect{type: :apply_aura, aura: aura}]}
        assert Spell.binary?(spell)
        refute Spell.binary?(%{spell | school: :physical})
        refute Spell.binary?(%{spell | school: 0})
        refute Spell.binary?(%{spell | dmg_class: 2})
        refute Spell.binary?(%{spell | dmg_class: 3})
      end

      for type <- [:interrupt_cast, :knockback] do
        assert Spell.binary?(%{frostbolt() | effects: [%Effect{type: type}]})
      end

      compiled = Semantics.compile(frostbolt())
      filtered = %{compiled | effects: [hd(compiled.effects)]}
      assert Spell.binary?(filtered)
      refute Spell.binary?(%{filtered | semantics: nil})

      for id <- [26_143, 26_478] do
        assert Spell.binary?(%Spell{id: id, school: :nature, dmg_class: 1})
      end
    end

    test "ordinary damage and damage over time remain nonbinary" do
      for effect <- [
            %Effect{type: :school_damage},
            %Effect{type: :apply_aura, aura: :periodic_damage},
            %Effect{type: :apply_aura, aura: :periodic_leech}
          ] do
        refute Spell.binary?(%{frostbolt() | effects: [effect]})
      end
    end
  end

  describe "magic_hit_chance_bp/4" do
    test "combines school resistance with hit and mechanic modifiers before final caps" do
      assert SpellResist.magic_hit_chance_bp(60, 60, false, binary_resistance: 100) == 7_200
      assert SpellResist.magic_hit_chance_bp(60, 60, false, binary_resistance: 300) == 2_400

      assert SpellResist.magic_hit_chance_bp(60, 60, false,
               binary_resistance: 300,
               hit_bonus: 10,
               mechanic_resistance: 25
             ) == 2_025

      assert SpellResist.magic_hit_chance_bp(60, 1, false, binary_resistance: 300) == 3_875
      assert SpellResist.magic_hit_chance_bp(60, 63, false, binary_resistance: 0) == 8_300
      assert SpellResist.magic_hit_chance_bp(60, 63, true, binary_resistance: 0) == 8_700
      assert SpellResist.magic_hit_chance_bp(60, 60, false, hit_bonus: -100, binary_resistance: 300) == 100
    end
  end

  describe "spell_hit?/5" do
    test "uses matching resistance and penetration without adding innate creature resistance" do
      caster = entity(1)
      target = %{level: 60, school_resistances: %{4 => 300, 2 => 100}}
      spell = frostbolt()
      assert SpellResist.spell_hit?(caster, spell, target, false, roll: 2_399)
      refute SpellResist.spell_hit?(caster, spell, target, false, roll: 2_400)

      caster = %{caster | unit: %{caster.unit | equipment_bonuses: %{resistance_penetration: [{16, -300}]}}}
      assert SpellResist.spell_hit?(caster, spell, target, false, roll: 9_599)
      refute SpellResist.spell_hit?(caster, %{spell | school: :fire}, target, false, roll: 9_599)

      assert SpellResist.spell_hit?(caster, spell, %{target | level: 63}, false, roll: 8_299)
      refute SpellResist.spell_hit?(caster, spell, %{target | level: 63}, false, roll: 8_300)

      assert SpellResist.spell_hit?(entity(1), %{spell | effects: [hd(spell.effects)]}, target, false, roll: 9_599)
      assert SpellResist.spell_hit?(entity(1), spell, Map.put(target, :no_spell_defense?, true), false, roll: 9_999)
      assert SpellResist.spell_hit?(entity(1), spell, Map.put(target, :alive?, false), false, roll: 9_999)

      assert SpellResist.spell_hit?(
               entity(1),
               %{spell | attributes: MapSet.new([:always_hit])},
               target,
               false,
               roll: 9_999
             )
    end
  end

  describe "receive/4" do
    test "a successful binary spell lands full damage and its slow while a resist lands neither" do
      spell = frostbolt()
      target = entity(2)
      context = %CastContext{caster_guid: 1, caster_level: 60, spell: spell}
      {hit, events} = SpellEffect.receive(target, context, spell, 1_000)
      assert hit.unit.health == 9_900
      assert Aura.has_aura?(hit, :mod_decrease_speed)
      assert Enum.any?(events, &match?(%Effects.SpellDamage{damage: 100, resisted: 0}, &1))

      {missed, events} = SpellEffect.receive(target, %{context | hit_outcome: :resist}, spell, 1_000)
      assert missed.unit.health == 10_000
      refute Aura.has_aura?(missed, :mod_decrease_speed)
      assert [%Effects.SpellLogMiss{reason: :resist}] = events

      shield = %Spell{
        id: 90_103,
        duration_ms: 10_000,
        effects: [%Effect{type: :apply_aura, aura: :school_absorb, base_points: 40, misc_value: 16}]
      }

      {shielded, _events} = Aura.apply_spell(target, 2, 60, shield, 0)
      {hit, events} = SpellEffect.receive(shielded, context, spell, 1_000)
      assert hit.unit.health == 9_940
      assert Enum.any?(events, &match?(%Effects.SpellDamage{resisted: 0, absorbed: 40}, &1))
      refute Aura.has_aura?(hit, :school_absorb)
    end
  end

  describe "tick/2" do
    test "binary channel damage skips partial resistance and cancellation stops further ticks" do
      spell = %{
        frostbolt()
        | attributes: MapSet.new([:channeled]),
          effects: [
            %Effect{index: 0, type: :apply_aura, aura: :periodic_damage, base_points: 100, amplitude_ms: 1_000},
            %Effect{index: 1, type: :apply_aura, aura: :mod_decrease_speed, base_points: -51}
          ]
      }

      {target, _events} = Aura.apply_spell(entity(2), 1, 60, spell, 0)
      {target, events} = Aura.tick(target, 1_000)
      assert target.unit.health == 9_900
      assert Enum.any?(events, &match?(%Effects.SpellDamage{periodic?: true, damage: 100, resisted: 0}, &1))
      {target, _events} = Aura.remove_spells(target, [spell.id], 1_100)
      {target, []} = Aura.tick(target, 2_000)
      assert target.unit.health == 9_900
      assert target.unit.auras == []
      assert Aura.next_event_at(target) == nil
    end
  end

  describe "complete/3" do
    test "launch reads resistance metadata and observes its removal" do
      caster_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))
      target_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

      caster_faction = %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, enemy_group: 1}
      target_faction = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, enemy_group: 12}

      for {guid, faction} <- [{caster_guid, caster_faction}, {target_guid, target_faction}] do
        Metadata.put(guid, %{
          alive?: true,
          faction_template: faction,
          faction_can_have_reputation?: false,
          unit_flags: 0,
          level: 60,
          school_resistances: %{4 => 300}
        })
      end

      on_exit(fn ->
        Metadata.delete(caster_guid)
        Metadata.delete(target_guid)
      end)

      spell = frostbolt()
      cast = %Cast{spell: spell, targets: Target.unit(target_guid), ends_at: 1_000}
      caster = entity(caster_guid)
      caster = %{caster | internal: %{caster.internal | casting: cast}}
      :rand.seed(:exsss, {1, 1, 66})
      missed = Casting.complete(caster, cast, 1_000)

      assert Enum.any?(
               missed.internal.events,
               &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :resist}}, &1)
             )

      Metadata.update(target_guid, %{school_resistances: %{4 => 0}})
      :rand.seed(:exsss, {1, 1, 66})
      hit = Casting.complete(caster, cast, 1_000)
      assert Enum.any?(hit.internal.events, &match?(%Effects.DeliverSpell{cast_context: %{hit_outcome: :hit}}, &1))
    end
  end

  defp frostbolt do
    %Spell{
      id: 90_101,
      school: :frost,
      dmg_class: 1,
      duration_ms: 5_000,
      effects: [
        %Effect{index: 0, type: :school_damage, base_points: 100, implicit_target_a: :target_enemy},
        %Effect{
          index: 1,
          type: :apply_aura,
          aura: :mod_decrease_speed,
          base_points: -51,
          implicit_target_a: :target_enemy
        }
      ]
    }
  end

  defp entity(guid) do
    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 10_000, max_health: 10_000, frost_resistance: 300},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}}
    }
  end
end
