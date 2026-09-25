defmodule ThistleTea.Game.Entity.Logic.CreatureEventTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureEvent
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment
  alias ThistleTea.Game.GameEvent.CreatureData
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:creatures]

  describe "reconcile/4" do
    test "changes a living actor and restores its original archetype", %{mob: mob, event: event} do
      mob = %{mob | unit: %{mob.unit | health: 25}, internal: %{mob.internal | threat: %{7 => 50}, in_combat: true}}
      changed = reconcile(mob, event)
      assert changed.object.guid == mob.object.guid
      assert changed.object.entry == 20
      assert changed.unit.native_display_id == 200
      assert changed.unit.health == 100
      assert changed.unit.max_health == 400
      assert changed.internal.creature.db_guid == 555
      assert changed.internal.threat == mob.internal.threat
      assert changed.internal.in_combat
      assert changed.internal.name == "Event form"
      assert changed.internal.spawn.event_data == event
      assert changed.internal.broadcast_update?

      restored = reconcile(changed, nil)
      assert restored.object == mob.object
      assert restored.unit.health == 25
      assert restored.unit.max_health == 100
      assert restored.unit.native_display_id == 100
      assert restored.internal.name == "Original"
      assert restored.internal.spawn.event_data == nil
    end

    test "does not reroll unchanged events or disturb unrelated script changes", %{mob: mob, event: event} do
      assert reconcile(mob, nil) == mob
      changed = reconcile(mob, event)
      assert CreatureEvent.reconcile(changed, event, 2_000, Random.fixed(0.99)) == changed
    end

    test "restores an empty spell list and resets changed spell timers", %{mob: mob, event: event} do
      [{weight, template}] = event.archetypes

      template = %{
        template
        | creature: %{template.creature | spell_list_id: 20, spells: [%CreatureSpell{spell_id: 82}]}
      }

      event = %{event | archetypes: [{weight, template}]}
      blackboard = Blackboard.put_spell_timer(Blackboard.new(), 0, 10_000, 0)
      mob = %{mob | internal: %{mob.internal | blackboard: blackboard}}
      changed = reconcile(mob, event)
      assert changed.internal.creature.spells == [%CreatureSpell{spell_id: 82}]
      assert changed.internal.blackboard.spells.timers == nil
      restored = reconcile(changed, nil)
      assert restored.internal.creature.spells == mob.internal.creature.spells
      assert restored.internal.creature.spell_list_id == mob.internal.creature.spell_list_id
    end

    test "changes equipment on the same entry and makes it the script reset default", %{mob: mob} do
      item = %ItemTemplate{display_id: 777, class: 2, subclass: 7, material: 1, inventory_type: 13, sheath: 3}
      event = %CreatureData{event: 27, equipment: [{1, [item, nil, nil]}]}
      changed = reconcile(mob, event)
      assert changed.object.entry == mob.object.entry
      assert changed.unit.virtual_item_slot_display == 777
      unequipped = %{changed | unit: ScriptEquipment.apply(changed.unit, [nil, nil, nil])}
      assert ScriptEquipment.reset(unequipped).unit.virtual_item_slot_display == 777
      restored = reconcile(changed, nil)
      assert restored.unit.virtual_item_slot_display == mob.unit.virtual_item_slot_display
      assert restored.internal.creature.default_equipment == mob.internal.creature.default_equipment
    end

    test "recomputes explicit event models through active scale modifiers", %{mob: mob} do
      {mob, _} = Aura.apply_spell(mob, 1, 60, aura(71, :mod_scale, 50), 0)
      model = %Model{display_id: 300, scale: 2.0, bounding_radius: 0.5, combat_reach: 2.0}
      event = %CreatureData{event: 2, model: model}
      changed = reconcile(mob, event)
      assert changed.unit.display_id == 300
      assert changed.object.scale_x == 3.0
      assert changed.unit.bounding_radius == 1.5
      assert changed.unit.combat_reach == 6.0
      {unscaled, _} = Aura.remove_spells(changed, [71], 2_000)
      assert unscaled.object.scale_x == 2.0
      restored = reconcile(changed, nil)
      assert restored.unit.display_id == mob.unit.display_id
      assert restored.object.scale_x == mob.object.scale_x

      configured = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | scale_override: 0.5}}}
      assert reconcile(configured, event).object.scale_x == 0.75
    end

    test "removes opposite auras and emits both event spell transitions", %{mob: mob} do
      start_spell = aura(71, :mod_melee_haste, 50)
      end_spell = aura(72, :mod_scale, 50)
      event = %CreatureData{event: 2, spell_start: 71, spell_end: 72, spellbook: %{71 => start_spell, 72 => end_spell}}
      {mob, _} = Aura.apply_spell(mob, mob.object.guid, 20, end_spell, 0)
      changed = reconcile(mob, event)
      refute Enum.any?(changed.unit.auras, &(&1.spell.id == 72))
      assert trigger_ids(changed) == [71]
      assert changed.internal.spellbook[71] == start_spell
      changed = %{changed | internal: %{changed.internal | events: []}}
      {changed, _} = Aura.apply_spell(changed, changed.object.guid, 20, start_spell, 1_000)
      restored = reconcile(changed, nil)
      refute Enum.any?(restored.unit.auras, &(&1.spell.id == 71))
      assert trigger_ids(restored) == [72]
    end

    test "preserves transform equipment across event changes", %{mob: mob} do
      item = %ItemTemplate{display_id: 777, class: 2, subclass: 7, material: 1, inventory_type: 13, sheath: 3}
      model = %Model{display_id: 300, equipment: [item, nil, nil]}

      spell = %Spell{
        id: 71,
        duration_ms: 30_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :transform, appearance: model}]
      }

      {mob, _} = Aura.apply_spell(mob, 1, 60, spell, 0)
      changed = reconcile(mob, %CreatureData{event: 27, equipment: []})
      assert changed.unit.display_id == 300
      assert changed.unit.virtual_item_slot_display == 777
      {removed, _} = Aura.remove_spells(changed, [71], 2_000)
      assert removed.unit.virtual_item_slot_display == 0
      assert removed.unit.display_id == 100
      restored = reconcile(removed, nil)

      assert restored.unit.virtual_item_slot_display ==
               mob.internal.creature.default_equipment.virtual_item_slot_display

      assert restored.unit.display_id == 100
    end

    test "keeps corpses dead and reapplies the active event after respawn", %{mob: mob, event: event} do
      corpse = %{mob | unit: %{mob.unit | health: 0}, internal: %{mob.internal | death_finalized?: true}}
      changed = reconcile(corpse, event)
      assert changed.unit.health == 0
      assert changed.internal.death_finalized?
      respawned = changed |> Mob.respawn() |> reconcile(event)
      assert respawned.object.entry == 20
      assert respawned.unit.health == 400
      refute respawned.internal.death_finalized?
      assert respawned.internal.spawn.event_data == event
      assert reconcile(respawned, nil).unit.health == 100
    end
  end

  describe "CreatureData.select/2" do
    test "selects the first active variant and reveals the next when it ends" do
      first = %CreatureData{event: 2}
      second = %CreatureData{event: 49}
      assert CreatureData.select([second, first], [49, 2]) == first
      assert CreatureData.select([second, first], [49]) == second
      assert CreatureData.select([second, first], []) == nil
    end
  end

  defp creatures(_context) do
    mob = build(10, "Original", 100, 100)
    template = build(20, "Event form", 200, 400) |> CreatureArchetype.from_mob()
    %{mob: mob, event: %CreatureData{event: 49, entry: 20, archetypes: [{1, template}]}}
  end

  defp build(entry, name, display, health) do
    %Mangos.Creature{
      guid: 555,
      id: entry,
      modelid: display,
      curhealth: health,
      selected_level: 20,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: entry,
        name: name,
        min_level: 20,
        max_level: 20,
        scale: 0,
        faction_alliance: 35,
        melee_base_attack_time: 2_000
      }
    }
    |> Mob.build()
  end

  defp aura(id, type, amount),
    do: %Spell{
      id: id,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount}]
    }

  defp reconcile(mob, event), do: CreatureEvent.reconcile(mob, event, 1_000, Random.fixed())

  defp trigger_ids(mob) do
    for %Effects.TriggerSpell{spell_id: id} <- mob.internal.events, do: id
  end
end
