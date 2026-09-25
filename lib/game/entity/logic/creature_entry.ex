defmodule ThistleTea.Game.Entity.Logic.CreatureEntry do
  @moduledoc "Changes a creature archetype while retaining its identity, engagement, and spawn lifecycle."

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Appearance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ObjectSync
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.CreatureMovement
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment

  @retained_unit_fields [
    :charm,
    :summon,
    :charmed_by,
    :summoned_by,
    :created_by,
    :target,
    :persuaded,
    :channel_object,
    :channel_spell,
    :created_by_spell,
    :mount_display_id,
    :auras,
    :aura_state,
    :stand_state,
    :npc_emote_state,
    :vis_flag,
    :pet_number,
    :pet_name_timestamp,
    :pet_experience,
    :pet_next_level_exp,
    :pet_loyalty,
    :pet_flags,
    :training_points,
    :equipment_bonuses,
    :power2,
    :power3,
    :power4,
    :power5
  ]
  @movement_inputs [
    :base_walk_speed,
    :base_run_speed,
    :base_run_back_speed,
    :base_swim_speed,
    :base_swim_back_speed
  ]

  def apply(%Mob{object: %{entry: entry}} = mob, %CreatureArchetype{entry: entry}, _now), do: mob

  def apply(%Mob{} = mob, %CreatureArchetype{} = template, now) when is_integer(now) do
    template =
      if template.creature.spell_list_id in [nil, 0],
        do: %{template | creature: %{template.creature | spells: mob.internal.creature.spells}},
        else: template

    replace(mob, template, now)
  end

  def apply(%Mob{} = mob, _template, _now), do: mob

  def replace(%Mob{} = mob, %CreatureArchetype{} = template, now) when is_integer(now) do
    previous = mob
    spawn = remember_template(mob)
    mob = remove_template_auras(mob, now)
    creature = creature_config(mob.internal.creature, template.creature)
    unit = retained_unit(mob.unit, template.unit, mob.internal.creature)

    mob = %{
      mob
      | object: %{mob.object | entry: template.entry, base_scale_x: template.scale},
        unit: unit,
        movement_block: copy_fields(mob.movement_block, template.movement, @movement_inputs),
        internal: %{
          mob.internal
          | name: template.name,
            creature: creature,
            loot: loot_config(mob.internal.loot, template.loot),
            spellbook: Map.merge(mob.internal.spellbook || %{}, template.spellbook || %{}),
            invincibility_health_threshold: template.invincibility_health_threshold,
            spawn: spawn
        }
    }

    mob
    |> apply_template_auras(now)
    |> then(&%{&1 | unit: Aura.sync_unit(&1.unit)})
    |> ScriptEquipment.reset()
    |> then(&Appearance.reconcile_equipment(&1, [], &1.unit.auras))
    |> preserve_resources(previous)
    |> ObjectSync.sync()
    |> sync_movement()
    |> CreatureMovement.sync()
    |> Reactive.sync_health()
    |> Core.mark_broadcast_update()
  end

  def restore(%Mob{internal: %{spawn: %Spawn{original_template: %CreatureArchetype{} = template} = spawn}} = mob) do
    %{
      mob
      | object: %{mob.object | entry: template.entry, base_scale_x: template.scale, scale_x: template.scale},
        internal: %{
          mob.internal
          | name: template.name,
            creature: restore_faction_tracking(template, mob.internal.creature),
            loot: template.loot,
            spellbook: template.spellbook,
            invincibility_health_threshold: template.invincibility_health_threshold,
            spawn: %{spawn | original_template: nil}
        }
    }
  end

  def restore(%Mob{} = mob), do: mob

  defp restore_faction_tracking(%CreatureArchetype{} = template, %Creature{} = current) do
    %{
      template.creature
      | script_faction_original: if(current.script_faction_original, do: template.unit.faction_template),
        script_faction_value: current.script_faction_value,
        script_faction_flags: current.script_faction_flags
    }
  end

  defp remember_template(%Mob{internal: %{spawn: %Spawn{original_template: nil} = spawn}} = mob),
    do: %{spawn | original_template: CreatureArchetype.from_mob(mob)}

  defp remember_template(%Mob{internal: %{spawn: %Spawn{} = spawn}}), do: spawn
  defp remember_template(%Mob{} = mob), do: %Spawn{original_template: CreatureArchetype.from_mob(mob)}

  defp retained_unit(current, template, creature) do
    flags = ((current.flags || 0) &&& bnot(creature.template_unit_flags || 0)) ||| (template.flags || 0)

    template
    |> copy_fields(current, @retained_unit_fields)
    |> then(&%{&1 | flags: flags, dynamic_flags: (current.dynamic_flags || 0) ||| (template.dynamic_flags || 0)})
  end

  defp creature_config(%Creature{} = current, %Creature{} = template) do
    template = %{
      template
      | db_guid: current.db_guid,
        ai_events: current.ai_events,
        stationary?: current.stationary?,
        addon_source: current.addon_source
    }

    if current.addon_source == :spawn, do: %{template | addon_auras: current.addon_auras}, else: template
  end

  defp loot_config(%Loot{} = current, %Loot{} = template) do
    %{
      current
      | id: template.id,
        pickpocket_id: template.pickpocket_id,
        skinning_id: template.skinning_id,
        min_gold: template.min_gold,
        max_gold: template.max_gold
    }
  end

  defp loot_config(nil, _template), do: nil

  defp remove_template_auras(%Mob{internal: %{creature: %Creature{addon_source: :spawn}}} = mob, _now), do: mob

  defp remove_template_auras(%Mob{} = mob, now) do
    ids = Enum.map(mob.internal.creature.addon_auras, & &1.id)
    {mob, events} = Aura.remove_spells(mob, ids, now)
    Effects.enqueue(mob, events)
  end

  defp apply_template_auras(%Mob{internal: %{creature: %Creature{addon_source: :spawn}}} = mob, _now), do: mob

  defp apply_template_auras(%Mob{} = mob, now) do
    Enum.reduce(mob.internal.creature.addon_auras, mob, fn spell, current ->
      {current, events} = Aura.apply_spell(current, current.object.guid, current.unit.level, spell, now)
      Effects.enqueue(current, events)
    end)
  end

  defp preserve_resources(%Mob{} = mob, %Mob{unit: previous}) do
    health = proportional(previous.health, previous.max_health, mob.unit.max_health)
    health = if previous.health > 0, do: max(health, 1), else: 0
    mana = proportional(previous.power1, previous.max_power1, mob.unit.max_power1)
    %{mob | unit: %{mob.unit | health: health, power1: mana}}
  end

  defp proportional(value, maximum, new_maximum)
       when is_number(value) and is_number(maximum) and maximum > 0 and is_number(new_maximum),
       do: min(trunc(value * new_maximum / maximum), new_maximum)

  defp proportional(_value, _maximum, _new_maximum), do: 0

  defp sync_movement(mob) do
    {mob, events} = MovementStats.sync(mob)
    Effects.enqueue(mob, events)
  end

  defp copy_fields(target, source, fields), do: struct!(target, Map.take(Map.from_struct(source), fields))
end
