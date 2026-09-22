defmodule ThistleTea.Game.Entity.Logic.ShamanTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Shaman
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defp shaman do
    %Mob{object: %Object{guid: 1}, unit: %Unit{level: 40}, internal: %Internal{}}
  end

  describe "trigger_weapon_enchant/5" do
    test "uses enchant chance for windfury and PPM for frostbrand" do
      payload = %{outcome: :normal, victim_guid: 2}
      windfury = %{effect: %{amount: 20, spell_id: 8233}, attack_time_ms: 2500}
      frostbrand = %{effect: %{amount: 0, spell_id: 8034}, attack_time_ms: 3000}

      triggered = Shaman.trigger_weapon_enchant(shaman(), payload, windfury, 0.0, fn -> 0.2 end)
      assert [%Effects.TriggerSpell{spell_id: 8233, target_guid: 2}] = triggered.internal.events

      triggered = Shaman.trigger_weapon_enchant(shaman(), payload, frostbrand, 9.0, fn -> 0.4 end)
      assert [%Effects.TriggerSpell{spell_id: 8034}] = triggered.internal.events

      unchanged = Shaman.trigger_weapon_enchant(shaman(), payload, frostbrand, 9.0, fn -> 0.5 end)
      assert unchanged.internal.events == []
    end

    test "does not proc from avoided attacks" do
      payload = %{outcome: :miss, victim_guid: 2}
      proc = %{effect: %{amount: 100, spell_id: 8026}, attack_time_ms: 2000}

      assert Shaman.trigger_weapon_enchant(shaman(), payload, proc, 0.0, fn -> 0.0 end).internal.events == []
    end

    test "beneficial permanent procs target the wielder and default to one PPM" do
      spell = %Spell{id: 20_007, effects: [%Effect{type: :apply_aura, aura: :mod_stat, implicit_target_a: :caster}]}
      proc = %{effect: %{amount: 0, spell_id: 20_007}, proc_spell: spell, attack_time_ms: 3000}
      payload = %{outcome: :normal, victim_guid: 2}
      triggered = Shaman.trigger_weapon_enchant(shaman(), payload, proc, 0.0, fn -> 0.04 end)
      assert [%Effects.TriggerSpell{spell_id: 20_007, target_guid: 1}] = triggered.internal.events
      assert Shaman.trigger_weapon_enchant(shaman(), payload, proc, 0.0, fn -> 0.06 end).internal.events == []
    end

    test "PPM overrides flat chance and successful glancing hits can proc" do
      proc = %{effect: %{amount: 100, spell_id: 20_007}, attack_time_ms: 3000}
      payload = %{outcome: :glancing, victim_guid: 2}
      assert Shaman.trigger_weapon_enchant(shaman(), payload, proc, 1.0, fn -> 0.06 end).internal.events == []

      assert [%Effects.TriggerSpell{}] =
               Shaman.trigger_weapon_enchant(shaman(), payload, proc, 1.0, fn -> 0.04 end).internal.events
    end
  end

  describe "flametongue_damage/3" do
    test "matches the VMangos weapon-speed and fire-power coefficient" do
      assert Shaman.flametongue_damage(325, 100, 2_000) == 14
      assert Shaman.flametongue_damage(325, 0, 4_000) == 13
    end
  end

  describe "resolve_weapon_enchant/5" do
    test "extra swings can proc ordinary enchants but cannot proc another Windfury batch" do
      spell = %Spell{id: 8233, effects: [%Effect{type: :add_extra_attacks, implicit_target_a: :caster}]}
      proc = %{effect: %{amount: 100, spell_id: 8233}, proc_spell: spell, attack_time_ms: 2000}
      payload = %{outcome: :normal, victim_guid: 2, extra_attack?: true}
      entity = shaman()
      assert {^entity, false} = Shaman.resolve_weapon_enchant(entity, payload, proc, 0.0, fn -> 0.0 end)
      proc = %{proc | proc_spell: %Spell{id: 20_007}}
      assert {triggered, true} = Shaman.resolve_weapon_enchant(entity, payload, proc, 0.0, fn -> 0.0 end)
      assert [%Effects.TriggerSpell{spell_id: 20_007, extra_attack?: true}] = triggered.internal.events
    end

    test "applies poison chance talents only to the matching spell family" do
      poison = %Spell{id: 8680, spell_family: 8, family_flags_0: 0x1000}

      talent = %Holder{
        spell: %Spell{id: 14_116, spell_family: 8},
        auras: [%Aura{type: :add_flat_modifier, misc_value: 18, amount: 10, class_mask: 0x1000}]
      }

      rogue = shaman()
      rogue = %{rogue | unit: %{rogue.unit | auras: [talent]}}
      proc = %{effect: %{amount: 20, spell_id: 8680}, proc_spell: poison, attack_time_ms: 2000}
      payload = %{outcome: :normal, victim_guid: 2}
      assert {_character, true} = Shaman.resolve_weapon_enchant(rogue, payload, proc, 0.0, fn -> 0.25 end)
      assert {^rogue, false} = Shaman.resolve_weapon_enchant(rogue, payload, proc, 0.0, fn -> 0.31 end)
      other = %{proc | proc_spell: %{poison | spell_family: 11}}
      assert {^rogue, false} = Shaman.resolve_weapon_enchant(rogue, payload, other, 0.0, fn -> 0.25 end)
    end
  end
end
