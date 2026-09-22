defmodule ThistleTea.Game.Entity.Logic.EnvironmentalDamageTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EnvironmentalDamage
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "apply/5" do
    test "uses the victim's own level and resistance penetration", %{character: character} do
      character = %{character | unit: %{character.unit | fire_resistance: 100}}
      assert EnvironmentalDamage.apply(character, :fire, 100, 1000, roll: 90).unit.health == 900
      assert EnvironmentalDamage.apply(character, :fire, 100, 1000, roll: 0).unit.health == 975
      character = with_aura(character, :mod_target_resistance, -100, 4)
      assert EnvironmentalDamage.apply(character, :fire, 100, 1000, roll: 0).unit.health == 900
    end

    test "resists before absorption and reports only remaining fire damage", %{character: character} do
      character = %{character | unit: %{character.unit | fire_resistance: 300}}
      character = with_aura(character, :school_absorb, 30, 4)
      burned = EnvironmentalDamage.apply(character, :fire, 200, 1000, roll: 0)
      assert burned.unit.health == 980
      assert burned.unit.auras == []
      assert [%Effects.EnvironmentalDamage{type: :fire, damage: 20, resisted: 150, absorbed: 30}] = feedback(burned)
      refute burned.internal.in_combat
      assert burned.unit.power2 == 0
      refute Enum.any?(burned.internal.events, &is_struct(&1, Effects.DurabilityDamage))
    end

    test "depletes shields across successive pulses without double absorption", %{character: character} do
      protected = with_aura(character, :school_absorb, 150, 4)
      first = EnvironmentalDamage.apply(protected, :fire, 100, 1000)
      assert first.unit.health == 1000
      assert [%Effects.EnvironmentalDamage{damage: 0, absorbed: 100}] = feedback(first)
      assert hd(hd(first.unit.auras).auras).amount == 50
      second = first |> clear_events() |> EnvironmentalDamage.apply(:fire, 100, 2000)
      assert second.unit.health == 950
      assert second.unit.auras == []
      assert [%Effects.EnvironmentalDamage{damage: 50, absorbed: 50}] = feedback(second)
    end

    test "matches shield schools and consumes mana shield resources", %{character: character} do
      physical_shield = with_aura(character, :school_absorb, 100, 1)
      burned = EnvironmentalDamage.apply(physical_shield, :fire, 100, 1000)
      assert burned.unit.health == 900
      assert burned.unit.auras == physical_shield.unit.auras
      protected = with_aura(character, :mana_shield, 100, 4, multiple_value: 2)
      burned = EnvironmentalDamage.apply(protected, :fire, 100, 1000)
      assert burned.unit.health == 950
      assert burned.unit.power1 == 0
      assert [%Effects.EnvironmentalDamage{damage: 50, absorbed: 50}] = feedback(burned)
    end

    test "fall drowning and exhaustion bypass shields and resistance", %{character: character} do
      protected = with_aura(character, :school_absorb, 500, 127)

      for type <- [:fall, :drowning, :exhaustion] do
        damaged = EnvironmentalDamage.apply(protected, type, 100, 1000)
        assert damaged.unit.health == 900
        assert damaged.unit.auras == protected.unit.auras
        assert [%Effects.EnvironmentalDamage{type: ^type, damage: 100, absorbed: 0, resisted: 0}] = feedback(damaged)
      end
    end

    test "lava uses fire protection and slime uses nature protection", %{character: character} do
      protected = with_aura(character, :school_absorb, 100, 4)
      assert EnvironmentalDamage.apply(protected, :lava, 100, 1000).unit.health == 1000
      assert EnvironmentalDamage.apply(protected, :slime, 100, 1000).unit.health == 900
      protected = with_aura(character, :school_absorb, 100, 8)
      assert EnvironmentalDamage.apply(protected, :slime, 100, 1000).unit.health == 1000
    end

    test "ignores outgoing and incoming damage multipliers", %{character: character} do
      protected = with_aura(character, :mod_damage_percent_taken, -100, 4)
      assert EnvironmentalDamage.apply(protected, :fire, 100, 1000).unit.health == 900
    end

    test "immune dead ghost and godmode players take no damage or feedback", %{character: character} do
      for protected <- [
            with_aura(character, :damage_immunity, 0, 4),
            with_aura(character, :school_immunity, 0, 4),
            %{character | unit: %{character.unit | health: 0}},
            %{character | player: %{character.player | flags: 0x10}},
            %{character | internal: %{character.internal | godmode: true}}
          ] do
        assert EnvironmentalDamage.apply(protected, :fire, 100, 1000) == protected
      end
    end

    test "fully absorbed fire breaks stealth and sitting but preserves feign death", %{character: character} do
      protected = with_aura(character, :school_absorb, 100, 4)
      stealth = %Holder{spell: %Spell{id: 1784}, auras: [%Aura{type: :mod_stealth, amount: 1}]}

      feign = %Holder{
        spell: %Spell{id: 5384, aura_interrupt_flags: 15_420},
        auras: [%Aura{type: :feign_death, amount: 1}]
      }

      protected = %{
        protected
        | unit: %{protected.unit | auras: [stealth, feign | protected.unit.auras], stand_state: 1}
      }

      burned = EnvironmentalDamage.apply(protected, :fire, 100, 1000)
      assert burned.unit.health == 1000
      assert burned.unit.stand_state == 0
      assert Enum.map(burned.unit.auras, & &1.spell.id) == [5384]
      assert Enum.any?(burned.internal.events, &is_struct(&1, Effects.StandState))
    end

    test "lethal fire enters death once with environmental durability loss", %{character: character} do
      dead = EnvironmentalDamage.apply(character, :fire, 1100, 1000)
      assert dead.unit.health == 0
      assert %Effects.DurabilityDamage{source_guid: nil, lethal?: true, environmental?: true} in dead.internal.events
      assert %Effects.MovementRootChanged{rooted?: true} in dead.internal.events
      assert EnvironmentalDamage.apply(dead, :fire, 1100, 2000) == dead
    end
  end

  describe "SpellEffect.receive/4" do
    test "environmental spells ignore caster damage bonuses and crit", %{character: character} do
      spell = %Spell{
        id: 7897,
        school: :fire,
        effects: [%Effect{type: :environmental_damage, base_points: 100, die_sides: 1}]
      }

      context = %CastContext{
        caster_guid: 2,
        caster_level: 1,
        spell_damage_bonus: %{fire: 900},
        damage_done_multiplier: 5.0,
        spell_crit_chance: 100.0
      }

      {burned, events} = SpellEffect.receive(character, context, spell, 1000)
      assert burned.unit.health == 900
      assert events == []
      assert [%Effects.EnvironmentalDamage{type: :fire, damage: 100}] = feedback(burned)
      refute burned.internal.in_combat
      refute Enum.any?(burned.internal.events, &is_struct(&1, Effects.SpellDamage))
    end

    test "nonplayers receive absorb and spell feedback without player environmental health loss", %{
      character: character
    } do
      protected = with_aura(character, :school_absorb, 50, 4)
      mob = %Mob{object: %Object{guid: 3}, unit: protected.unit, internal: %Internal{}}

      spell = %Spell{
        id: 7897,
        school: :fire,
        effects: [%Effect{type: :environmental_damage, base_points: 100, die_sides: 1}]
      }

      {burned, events} = SpellEffect.receive(mob, %CastContext{caster_guid: 2, caster_level: 60}, spell, 1000)
      assert burned.unit.health == 1000
      assert burned.unit.auras == []
      assert [%Effects.SpellDamage{damage: 100, absorbed: 50, proc_type: nil, crit?: false}] = events
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{
          health: 1000,
          max_health: 1000,
          level: 60,
          auras: [],
          power1: 100,
          max_power1: 100,
          power2: 0,
          power_type: 1,
          fire_resistance: 0,
          nature_resistance: 0
        },
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp with_aura(character, type, amount, mask, opts \\ []) do
    aura = %Aura{type: type, amount: amount, misc_value: mask, multiple_value: Keyword.get(opts, :multiple_value, 0)}
    holder = %Holder{spell: %Spell{id: 999}, caster_guid: 1, auras: [aura]}
    %{character | unit: %{character.unit | auras: [holder]}}
  end

  defp feedback(character), do: Enum.filter(character.internal.events, &is_struct(&1, Effects.EnvironmentalDamage))
  defp clear_events(character), do: %{character | internal: %{character.internal | events: []}}
end
