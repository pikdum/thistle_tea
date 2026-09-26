defmodule ThistleTea.Game.Entity.Logic.ProcChanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcChance
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "chance/4" do
    test "outgoing PPM uses the current weapon or form period before haste", %{character: character} do
      spell = %{proc_spell() | proc_chance: 10, proc_rule: %ProcRule{ppm_rate: 6, custom_chance: 7}}

      for {context, expected} <- [
            {%{}, 20},
            {%{hand: :offhand}, 10},
            {%{spell: %Spell{dmg_class: 3}}, 30},
            {%{spell: %Spell{attributes: MapSet.new([:auto_repeat])}}, 30},
            {%{spell: %Spell{dmg_class: 2, attributes: MapSet.new([:requires_offhand_weapon])}}, 10}
          ] do
        assert ProcChance.chance(character, spell, :outgoing, context) == expected
      end

      assert ProcChance.chance(character, spell, :incoming, %{hand: :ranged}) == 7
      spell = %{spell | proc_rule: %{spell.proc_rule | custom_chance: 0}}
      assert ProcChance.chance(character, spell, :incoming, %{}) == 10

      for {form, expected} <- [{1, 10}, {5, 25}, {8, 25}] do
        feral = %{character | unit: %{character.unit | class: 11, shapeshift_form: form}}
        assert ProcChance.chance(feral, spell, :outgoing, %{}) == expected
      end
    end

    test "applies matching flat then percent modifiers after custom and PPM rates", %{character: character} do
      character = with_modifiers(character, [modifier(5), modifier(50, :add_pct_modifier)])
      spell = %{proc_spell() | proc_rule: %ProcRule{ppm_rate: 6, custom_chance: 7}}
      assert ProcChance.chance(character, spell, :outgoing, %{}) == 37.5
      assert ProcChance.chance(character, spell, :incoming, %{}) == 18
      assert ProcChance.chance(character, %{spell | spell_family: 8}, :incoming, %{}) == 7
      assert ProcChance.chance(character, %{spell | family_flags_0: 2}, :incoming, %{}) == 7
    end

    test "does not cap PPM before a negative chance modifier", %{character: character} do
      character = with_modifiers(character, [modifier(-150)])
      spell = %{proc_spell() | proc_rule: %ProcRule{ppm_rate: 60}}
      assert ProcChance.chance(character, spell, :outgoing, %{}) == 50
      assert ProcChance.roll?(character, spell, :outgoing, %{}, fn -> 0.5 end)
      refute ProcChance.roll?(character, spell, :outgoing, %{}, fn -> 0.5001 end)
    end

    test "inherits the pet owner's current spell modifiers", %{character: character} do
      pet = %Pet{owner_spell_modifiers: [modifier(100)]}
      character = %{character | internal: %{character.internal | pet: pet}}
      assert ProcChance.chance(character, proc_spell(), :incoming, %{}) == 100
      character = %{character | internal: %{character.internal | pet: %{pet | owner_spell_modifiers: []}}}
      assert ProcChance.chance(character, proc_spell(), :incoming, %{}) == 0
    end
  end

  describe "apply_spell/4" do
    test "keeps the base chance and uses the bearer's changing modifiers", %{character: character} do
      spell = proc_spell()
      context = %CastContext{caster_guid: 2, caster_level: 60, spell_modifiers: modifier(80).auras}
      {character, _} = Aura.apply_spell(character, context, spell, 0)
      assert [%Holder{spell: %{proc_chance: 0}} = holder] = character.unit.auras

      for amount <- [5, 10, 0] do
        current = with_modifiers(character, [modifier(amount)])
        assert ProcChance.chance(current, holder.spell, :outgoing, %{}) == amount
        assert Enum.find(current.unit.auras, &(&1.spell.id == spell.id)) == holder
      end

      refute ProcChance.roll?(character, holder.spell, :outgoing, %{}, fn -> 0 end)
    end
  end

  describe "receive/4" do
    test "ranged feedback rolls PPM once and retains charge and cooldown bookkeeping", %{character: character} do
      spell = %{proc_spell() | proc_rule: %ProcRule{ppm_rate: 20, cooldown_ms: 5_000}}
      {character, _} = Aura.apply_spell(character, 1, 60, spell, 0)
      shot = %Spell{id: 75, dmg_class: 3}
      payload = %{victim_guid: 2, proc_type: :deal_ranged_attack, outcome: :normal, damage: 30}
      procced = SpellFeedback.receive(character, payload, shot, 1_000)
      assert [%Effects.TriggerSpell{spell_id: 9002}] = procced.internal.events
      assert [%Holder{charges: 1, next_proc_at: 6_000}] = procced.unit.auras
      {procced, _} = Effects.drain(procced)
      assert SpellFeedback.receive(procced, payload, shot, 2_000) == procced
      exhausted = SpellFeedback.receive(procced, payload, shot, 6_000)
      assert exhausted.unit.auras == []
      assert [%Effects.TriggerSpell{spell_id: 9002}] = exhausted.internal.events
    end
  end

  describe "reactions/3" do
    test "incoming PPM uses the fixed chance with live modifiers for spells and swings", %{character: character} do
      spell = %{proc_spell() | proc_rule: %ProcRule{ppm_rate: 0.01, custom_chance: 10, cooldown_ms: 5_000}}
      {character, _} = Aura.apply_spell(character, 1, 60, spell, 0)
      guaranteed = with_modifiers(character, [modifier(90)])
      blocked = with_modifiers(character, [modifier(-10)])

      for {event, context} <- [
            {:hit_taken, %{proc_type: :take_melee_swing}},
            {:spell_hit_taken, %{proc_type: :take_harmful_spell, spell: %Spell{id: 133}}}
          ] do
        context = Map.merge(context, %{attacker_guid: 2, outcome: :normal, damage: 30, now: 1_000})
        {procced, events} = Aura.reactions(guaranteed, event, context)
        assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 9002}, &1))
        assert Enum.find(procced.unit.auras, &(&1.spell.id == spell.id)).charges == 1
        assert {^blocked, []} = Aura.reactions(blocked, event, context)
      end
    end

    test "removing a talent stops active outgoing and kill procs without spending charges", %{character: character} do
      {character, _} = Aura.apply_spell(character, 1, 60, proc_spell(), 0)
      empowered = with_modifiers(character, [modifier(100)])

      for {event, context} <- [
            {:kill, %{}},
            {:melee_hit_dealt, %{proc_type: :deal_melee_swing}},
            {:spell_hit_dealt, %{proc_type: :deal_ranged_attack, spell: %Spell{id: 75, dmg_class: 3}}}
          ] do
        context = Map.merge(context, %{victim_guid: 2, outcome: :normal, now: 1_000})
        {procced, events} = Aura.reactions(empowered, event, context)
        assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 9002}, &1))
        assert Enum.find(procced.unit.auras, &(&1.spell.id == 9001)).charges == 1
        assert {^character, []} = Aura.reactions(character, event, context)
      end
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        internal: %Internal{},
        unit: %Unit{
          level: 60,
          class: 3,
          health: 100,
          max_health: 100,
          auras: [],
          mainhand_weapon: %{class: 2, subclass: 7},
          base_melee_attack_time: 2_000,
          base_offhand_attack_time: 1_000,
          base_ranged_attack_time: 3_000,
          base_attack_time: 500,
          offhand_attack_time: 250,
          ranged_attack_time: 750
        }
      }
    }
  end

  defp proc_spell do
    %Spell{
      id: 9001,
      spell_family: 9,
      family_flags_0: 1,
      duration_ms: -1,
      proc_chance: 0,
      proc_charges: 2,
      proc_type_mask: 0x2004E,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 9002}]
    }
  end

  defp modifier(amount, type \\ :add_flat_modifier) do
    %Holder{
      spell: %Spell{id: 9003, spell_family: 9},
      caster_guid: 1,
      auras: [%AuraData{type: type, amount: amount, misc_value: 18, class_mask: 1}]
    }
  end

  defp with_modifiers(character, modifiers),
    do: %{character | unit: %{character.unit | auras: character.unit.auras ++ modifiers}}
end
