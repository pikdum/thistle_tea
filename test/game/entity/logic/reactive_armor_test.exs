defmodule ThistleTea.Game.Entity.Logic.ReactiveArmorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Aura.ReactiveArmor
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  describe "events/4" do
    test "Obsidian Armor covers all six magic schools and credits the bearer" do
      holder = holder(27_539)

      for {school, spell_id} <- [
            holy: 27_536,
            fire: 27_533,
            nature: 27_538,
            frost: 27_534,
            shadow: 27_535,
            arcane: 27_540
          ] do
        assert [%Effects.TriggerSpell{} = event] = ReactiveArmor.events([], holder, 1, %{spell: %Spell{school: school}})
        assert event.spell_id == spell_id
        assert event.source_guid == 1
        assert event.target_guid == 1
        assert event.cast_item_guid == 99
        assert event.triggering_spell_id == 27_539
        assert event.requires_living_target?
      end

      assert ReactiveArmor.events([], holder, 1, %{spell: %Spell{school: :physical}}) == []
      assert ReactiveArmor.events([], holder, 1, %{spell: nil}) == []
    end

    test "Adaptive Warding requires the current Mage Armor effect and excludes holy damage" do
      holder = holder(28_764)
      armor = mage_armor()

      for {school, spell_id} <- [fire: 28_765, nature: 28_768, frost: 28_766, shadow: 28_769, arcane: 28_770] do
        context = %{spell: %Spell{school: school}}
        assert [%Effects.TriggerSpell{spell_id: ^spell_id}] = ReactiveArmor.events([armor], holder, 1, context)
        assert ReactiveArmor.events([], holder, 1, context) == []
        assert ReactiveArmor.events([%{armor | auras: []}], holder, 1, context) == []
        assert ReactiveArmor.events([%{armor | spell: %{armor.spell | family_flags_0: 0}}], holder, 1, context) == []
      end

      for school <- [:physical, :holy] do
        assert ReactiveArmor.events([armor], holder, 1, %{spell: %Spell{school: school}}) == []
      end
    end
  end

  describe "reactions/3" do
    test "accepted spells spend charges once and respect the proc cooldown" do
      holder = %{holder(27_539) | charges: 2}
      entity = entity([holder])
      {entity, events} = AuraLogic.reactions(entity, :spell_hit_taken, hit(:fire, 1_000))
      assert [%Effects.TriggerSpell{spell_id: 27_533}] = triggers(events)
      assert [%{charges: 1, next_proc_at: 11_000}] = entity.unit.auras
      {unchanged, events} = AuraLogic.reactions(entity, :spell_hit_taken, hit(:frost, 10_999))
      assert triggers(events) == []
      assert unchanged.unit.auras == entity.unit.auras
      {consumed, events} = AuraLogic.reactions(entity, :spell_hit_taken, hit(:frost, 11_000))
      assert [%Effects.TriggerSpell{spell_id: 27_534}] = triggers(events)
      assert consumed.unit.auras == []
    end

    test "ineligible hits and missing armor spend neither charges nor cooldowns" do
      for {id, armor} <- [{27_539, []}, {28_764, [mage_armor()]}] do
        entity = entity([%{holder(id) | charges: 2} | armor])

        for context <- [
              hit(:physical, 1_000),
              %{hit(:fire, 1_000) | outcome: :resist},
              Map.put(hit(:fire, 1_000), :proc_origin, :suppressed),
              %{hit(:fire, 1_000) | proc_type: :take_harmful_periodic}
            ] do
          {unchanged, events} = AuraLogic.reactions(entity, :spell_hit_taken, context)
          assert triggers(events) == []
          assert unchanged.unit.auras == entity.unit.auras
        end
      end

      entity = entity([holder(28_764)])
      {unchanged, events} = AuraLogic.reactions(entity, :spell_hit_taken, hit(:fire, 1_000))
      assert triggers(events) == []
      assert unchanged.unit.auras == entity.unit.auras
    end
  end

  defp triggers(events), do: Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

  defp hit(school, now) do
    %{
      attacker_guid: 2,
      spell: %Spell{id: 133, school: school, dmg_class: 1},
      proc_type: :take_harmful_spell,
      outcome: :normal,
      damage: 10,
      now: now
    }
  end

  defp holder(id) do
    %Holder{
      spell: %Spell{id: id, proc_chance: 100, proc_type_mask: 0x20000, proc_rule: %ProcRule{cooldown_ms: 10_000}},
      auras: [%Aura{type: :dummy}],
      caster_guid: 7,
      caster_level: 60,
      cast_item_guid: 99
    }
  end

  defp mage_armor do
    %Holder{
      spell: %Spell{id: 6117, spell_family: 3, family_flags_0: 0x10000000},
      auras: [%Aura{type: :mod_mana_regen_interrupt}]
    }
  end

  defp entity(holders) do
    %Mob{object: %Object{guid: 1}, unit: %Unit{health: 100, max_health: 100, auras: holders}, internal: %Internal{}}
  end
end
