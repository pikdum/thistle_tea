defmodule ThistleTea.Game.Entity.Logic.CreatureEvent do
  @moduledoc "Reconciles world-event creature variants against the original spawn archetype."

  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.CreatureArchetype
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CreatureEntry
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment
  alias ThistleTea.Game.GameEvent.CreatureData

  def reconcile(%Mob{internal: %{spawn: %Spawn{event_data: data}}} = mob, data, _now, _random), do: mob

  def reconcile(%Mob{internal: %{spawn: %Spawn{} = spawn}} = mob, data, now, %Random{} = random) do
    baseline = spawn.original_template || CreatureArchetype.from_mob(mob)
    template = template(data, baseline, random)

    mob
    |> event_spells(spawn.event_data, false, now)
    |> CreatureEntry.replace(template, now)
    |> event_spells(data, true, now)
    |> reset_spell_timers(mob)
    |> then(&%{&1 | internal: %{&1.internal | spawn: %{&1.internal.spawn | event_data: data}}})
  end

  def reconcile(%Mob{} = mob, _data, _now, _random), do: mob

  defp template(nil, baseline, _random), do: baseline

  defp template(%CreatureData{} = data, baseline, random) do
    template = Random.weighted_choice(random, data.archetypes) || baseline

    template
    |> model(data.model)
    |> equipment(data.equipment, random)
  end

  defp model(template, nil), do: template

  defp model(%CreatureArchetype{} = template, %Model{} = model) do
    configured_scale = template.creature.scale_override
    scale = if is_number(configured_scale) and configured_scale > 0, do: configured_scale, else: model.scale

    unit = %{
      template.unit
      | native_display_id: model.display_id,
        display_id: model.display_id,
        base_bounding_radius: model.bounding_radius * scale,
        base_combat_reach: model.combat_reach * scale,
        bounding_radius: model.bounding_radius * scale,
        combat_reach: model.combat_reach * scale
    }

    %{template | unit: unit, scale: scale}
  end

  defp equipment(template, nil, _random), do: template

  defp equipment(%CreatureArchetype{} = template, choices, random) do
    items = Random.weighted_choice(random, choices) || [nil, nil, nil]
    unit = ScriptEquipment.apply(template.unit, items)
    default = Map.take(Map.from_struct(unit), [:virtual_item_slot_display, :virtual_item_info])
    %{template | unit: unit, creature: %{template.creature | default_equipment: default}}
  end

  defp event_spells(mob, nil, _activated?, _now), do: mob

  defp event_spells(mob, %CreatureData{} = data, activated?, now) do
    {remove, cast} = if activated?, do: {data.spell_end, data.spell_start}, else: {data.spell_start, data.spell_end}
    {mob, events} = Aura.remove_spells(mob, [remove], now)
    mob = Effects.enqueue(mob, events)
    mob = %{mob | internal: %{mob.internal | spellbook: Map.merge(mob.internal.spellbook || %{}, data.spellbook)}}

    if is_integer(cast) and cast > 0 do
      Effects.enqueue(mob, Effects.trigger_spell(mob.object.guid, mob.unit.level, mob.object.guid, cast))
    else
      mob
    end
  end

  defp reset_spell_timers(mob, previous) do
    if mob.internal.creature.spells == previous.internal.creature.spells do
      mob
    else
      blackboard = Blackboard.ensure(mob.internal.blackboard)
      blackboard = %{blackboard | spells: %{blackboard.spells | timers: nil, next_list_at: 0}}
      %{mob | internal: %{mob.internal | blackboard: blackboard}}
    end
  end
end
