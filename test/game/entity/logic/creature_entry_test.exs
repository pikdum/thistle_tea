defmodule ThistleTea.Game.Entity.Logic.CreatureEntryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureEntry
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.TemporaryFaction
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:creatures]

  describe "apply/3" do
    test "replaces archetype fields without replacing the actor", %{mob: mob, template: template} do
      cast = Cast.new(%Spell{id: 81, cast_time_ms: 5_000}, Target.unit(1), 0)
      loot = %{mob.internal.loot | tapped_by: %Tap{player: 1}, pockets: %{1 => :taken}}

      mob = %{
        mob
        | unit: %{mob.unit | health: 25, power1: 20, flags: 0x80000, target: 1},
          internal: %{mob.internal | casting: cast, loot: loot, in_combat: true, threat: %{1 => 50}}
      }

      changed = CreatureEntry.apply(mob, template, 1_000)

      assert changed.object.guid == mob.object.guid
      assert changed.object.entry == 20
      assert changed.object.scale_x == 2.0
      assert changed.internal.name == "New creature"
      assert changed.unit.level == 40
      assert changed.unit.faction_template == 35
      assert changed.unit.native_display_id == 200
      assert changed.unit.health == 100
      assert changed.unit.power1 == 60
      assert changed.unit.base_attack_time == 3_000
      assert changed.unit.fire_resistance == 50
      assert Bitwise.band(changed.unit.flags, 0x80000) != 0
      assert changed.unit.target == 1
      assert changed.internal.threat == %{1 => 50}
      assert changed.internal.in_combat
      assert changed.internal.casting == cast
      assert changed.internal.loot.tapped_by == loot.tapped_by
      assert changed.internal.loot.pockets == loot.pockets
      assert changed.internal.loot.id == 20
      assert changed.internal.creature.db_guid == mob.internal.creature.db_guid
      assert changed.internal.world == mob.internal.world
      assert changed.movement_block.position == mob.movement_block.position
      assert changed.movement_block.run_speed == 14.0
      assert changed.internal.spawn.incarnation_id == 123
      assert changed.internal.broadcast_update?
      assert Enum.any?(changed.internal.events, &match?(%Effects.MovementSpeedChanged{speed: 14.0}, &1))
    end

    test "retains and recomputes unrelated aura effects", %{mob: mob, template: template} do
      {mob, _events} = Aura.apply_spell(mob, 1, 60, aura(71, :mod_melee_haste, 50), 0)
      {mob, _events} = Aura.apply_spell(mob, 1, 60, aura(72, :mod_scale, 50), 0)
      changed = CreatureEntry.apply(mob, template, 1_000)
      assert Enum.map(changed.unit.auras, & &1.spell.id) == [71, 72]
      assert changed.unit.base_attack_time == 2_000
      assert changed.object.scale_x == 3.0
      assert changed.unit.health == 400
      {restored, _events} = Aura.remove_spells(changed, [71, 72], 2_000)
      assert restored.unit.base_attack_time == 3_000
      assert restored.object.scale_x == 2.0
    end

    test "replaces template auras and retains external spells", %{mob: mob, template: template} do
      old_aura = aura(71, :mod_melee_haste, 50)
      new_aura = aura(72, :mod_melee_haste, -25)
      mob = %{mob | internal: %{mob.internal | creature: %{mob.internal.creature | addon_auras: [old_aura]}}}
      mob = Mob.apply_addon_auras(mob, 0)
      {mob, _events} = Aura.apply_spell(mob, 1, 60, aura(73, :mod_scale, 10), 0)
      template = %{template | creature: %{template.creature | addon_auras: [new_aura]}}
      changed = CreatureEntry.apply(mob, template, 1_000)
      assert Enum.map(changed.unit.auras, & &1.spell.id) == [73, 72]
      assert changed.unit.base_attack_time == 3_750
    end

    test "spawn addon auras override changed templates", %{mob: mob, template: template} do
      spell = aura(71, :mod_melee_haste, 50)

      mob = %{
        mob
        | internal: %{mob.internal | creature: %{mob.internal.creature | addon_source: :spawn, addon_auras: [spell]}}
      }

      mob = Mob.apply_addon_auras(mob, 0)
      template = %{template | creature: %{template.creature | addon_auras: [aura(72, :mod_melee_haste, -25)]}}
      changed = CreatureEntry.apply(mob, template, 1_000)
      assert changed.internal.creature.addon_auras == [spell]
      assert changed.unit.auras == mob.unit.auras
      assert changed.unit.base_attack_time == 2_000
    end

    test "does not revive dead creatures or kill a living low-health creature", %{mob: mob, template: template} do
      dead = %{mob | unit: %{mob.unit | health: 0}, internal: %{mob.internal | death_finalized?: true}}
      changed = CreatureEntry.apply(dead, template, 1_000)
      assert changed.unit.health == 0
      assert changed.internal.death_finalized?
      small = %{template | unit: %{template.unit | health: 1, max_health: 1}}
      changed = CreatureEntry.apply(%{mob | unit: %{mob.unit | health: 1}}, small, 1_000)
      assert changed.unit.health == 1
    end

    test "ignores missing definitions and repeated entry changes", %{mob: mob, template: template} do
      assert CreatureEntry.apply(mob, nil, 1_000) == mob
      changed = CreatureEntry.apply(mob, template, 1_000)
      assert CreatureEntry.apply(changed, template, 2_000) == changed
    end

    test "retains original AI and preserves a list when the new template has none", %{mob: mob, template: template} do
      spell = %CreatureSpell{spell_id: 81}

      mob = %{
        mob
        | internal: %{mob.internal | creature: %{mob.internal.creature | spells: [spell], ai_events: [:original]}}
      }

      changed = CreatureEntry.apply(mob, template, 1_000)
      assert changed.internal.creature.spells == [spell]
      assert changed.internal.creature.ai_events == [:original]
    end
  end

  describe "Mob.respawn/1" do
    test "retains a later persistent faction override", %{mob: mob, template: template} do
      restored =
        mob
        |> CreatureEntry.apply(template, 1_000)
        |> TemporaryFaction.set(113, 0)
        |> Mob.respawn()
        |> TemporaryFaction.after_respawn()

      assert restored.object.entry == mob.object.entry
      assert restored.unit.faction_template == 113
      assert TemporaryFaction.clear(restored).unit.faction_template == 14
    end

    test "restores the original archetype after multiple changes", %{mob: mob, template: template} do
      intermediate = %{template | entry: 21, name: "Intermediate"}
      changed = mob |> CreatureEntry.apply(intermediate, 1_000) |> CreatureEntry.apply(template, 2_000)
      restored = Mob.respawn(changed)
      assert restored.object == mob.object
      assert restored.internal.name == mob.internal.name
      assert restored.internal.creature == mob.internal.creature
      assert restored.internal.loot == mob.internal.loot
      assert restored.internal.spellbook == mob.internal.spellbook
      assert restored.unit.health == 100
      assert restored.unit.native_display_id == 100
      assert restored.unit.faction_template == 14
      assert restored.internal.spawn.original_template == nil
    end
  end

  describe "Script.run/5" do
    test "equipment reset uses the current archetype", %{mob: mob, template: template} do
      equipment = %{virtual_item_slot_display: 333, virtual_item_info: <<0::192>>}

      template = %{
        template
        | unit: %{template.unit | virtual_item_slot_display: 333},
          creature: %{template.creature | default_equipment: equipment}
      }

      steps = [
        %ScriptStep{command: :update_entry, datalong: template.entry},
        %ScriptStep{command: :set_equipment, equipment_items: [nil, nil, nil]},
        %ScriptStep{command: :set_equipment, datalong: 1}
      ]

      context = Context.new(1_000, creature_archetypes: %{template.entry => [{1, template}]})
      {changed, _} = Script.run(mob, Blackboard.new(), steps, 0, context)
      assert changed.unit.virtual_item_slot_display == 333
      assert Mob.respawn(changed).unit.virtual_item_slot_display == mob.unit.virtual_item_slot_display
    end

    test "changes entry before the next same-batch command and resets spell timers", %{mob: mob, template: template} do
      template = %{
        template
        | creature: %{template.creature | spell_list_id: 20, spells: [%CreatureSpell{spell_id: 82}]}
      }

      step = %ScriptStep{command: :update_entry, datalong: 20}
      faction = %ScriptStep{command: :set_faction, datalong: 113}
      blackboard = Blackboard.new() |> Blackboard.put_spell_timer(0, 10_000, 0)
      context = Context.new(1_000, creature_archetypes: %{20 => [{1, template}]})
      {changed, blackboard} = Script.run(mob, blackboard, [step, faction], 0, context)
      assert changed.object.entry == 20
      assert changed.unit.faction_template == 113
      assert blackboard.spells.timers == nil
    end

    test "selects target entries from current perception", %{mob: mob} do
      guid = Guid.from_low_guid(:mob, 30, 55)
      observation = %Observation{guid: guid, metadata: %{entry: 20, alive?: true}}
      perception = Perception.new(0, nil, %{guid => observation}, %{mobs: [{guid, 1.0}]})
      condition = %ScriptStep{command: :terminate_script, datalong: 20}
      following = %ScriptStep{command: :stand_state, datalong: 7}

      {changed, _} =
        Script.run(mob, Blackboard.new(), [condition, following], 0, Context.new(0, perception: perception))

      assert changed.unit.stand_state == 7
    end
  end

  describe "Random.weighted_choice/2" do
    test "respects weighted intervals and empty choices" do
      assert Random.weighted_choice(Random.fixed(0.0), [{1, :a}, {3, :b}]) == :a
      assert Random.weighted_choice(Random.fixed(0.25), [{1, :a}, {3, :b}]) == :b
      assert Random.weighted_choice(Random.fixed(0.999), [{1, :a}, {3, :b}]) == :b
      assert Random.weighted_choice(Random.fixed(), []) == nil
    end

    test "selects the final interval when the runtime float reaches one" do
      random = %{Random.fixed() | float: fn -> 1.0 end}
      assert Random.weighted_choice(random, [{1, :a}, {3, :b}]) == :b
    end
  end

  defp creatures(_context) do
    mob =
      build(10,
        health: 100,
        mana: 80,
        level: 20,
        name: "Original creature",
        display: 100,
        scale: 1.0,
        faction: 14,
        speed: 2_000,
        run: 1.0
      )

    mob = %{
      mob
      | internal: %{mob.internal | world: WorldRef.instance(998, 7), spawn: %{mob.internal.spawn | incarnation_id: 123}}
    }

    target =
      build(20,
        health: 400,
        mana: 240,
        level: 40,
        name: "New creature",
        display: 200,
        scale: 2.0,
        faction: 35,
        speed: 3_000,
        run: 2.0
      )

    target = %{target | unit: %{target.unit | base_fire_resistance: 50, fire_resistance: 50}}
    %{mob: mob, template: CreatureArchetype.from_mob(target)}
  end

  defp build(entry, options) do
    options = Map.new(options)

    %Mangos.Creature{
      guid: 555,
      id: entry,
      modelid: options.display,
      curhealth: options.health,
      curmana: options.mana,
      selected_level: options.level,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: entry,
        name: options.name,
        min_level: options.level,
        max_level: options.level,
        scale: options.scale,
        faction_alliance: options.faction,
        melee_base_attack_time: options.speed,
        speed_run: options.run,
        loot_id: entry,
        min_melee_dmg: 10.0,
        max_melee_dmg: 20.0
      }
    }
    |> Mob.build()
  end

  defp aura(id, type, amount) do
    %Spell{
      id: id,
      duration_ms: 30_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount}]
    }
  end
end
