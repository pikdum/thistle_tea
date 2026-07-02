defmodule ThistleTea.Game.World.Loader.Mob do
  @moduledoc """
  Loads the creature spawns for a cell from Mangos (with templates, movement,
  and display info) into mob entity structs.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.AddonAuras
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.Creature.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.map(&load_creature/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.each(&start/1)
  end

  def load_creature(%Mangos.Creature{} = creature) do
    creature
    |> load_creature_template()
    |> load_creature_level()
    |> load_creature_class_level_stats()
    |> load_display()
    |> load_creature_movement()
    |> load_movement_scripts()
    |> load_ai_events()
    |> load_equip_items()
    |> load_spells()
    |> load_addon_auras()
  end

  defp load_creature_template(%Mangos.Creature{} = creature) do
    entry = creature |> template_pool() |> Enum.random()

    case Mangos.Repo.get(Mangos.CreatureTemplate, entry) do
      %Mangos.CreatureTemplate{} = template ->
        creature
        |> Map.put(:id, entry)
        |> Map.put(:creature_template, template)

      _ ->
        nil
    end
  end

  defp load_creature_level(nil), do: nil

  defp load_creature_level(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    Map.put(creature, :selected_level, Enum.random(template.min_level..template.max_level))
  end

  defp load_creature_class_level_stats(nil), do: nil

  defp load_creature_class_level_stats(
         %Mangos.Creature{creature_template: %Mangos.CreatureTemplate{unit_class: unit_class}} = creature
       ) do
    level = Map.get(creature, :selected_level)
    Map.put(creature, :creature_class_level_stats, Mangos.CreatureClassLevelStats.get(unit_class, level))
  end

  defp load_display(nil), do: nil

  defp load_display(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    {display_id, display_scale} = select_display(template)

    creature
    |> Map.put(:modelid, display_id)
    |> Map.put(:display_scale, display_scale || display_scale(display_id))
    |> Map.put(:creature_display_info_addon, Mangos.CreatureDisplayInfoAddon.get(display_id))
  end

  defp load_spells(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    template_spell_ids =
      Enum.filter([template.spell_id1, template.spell_id2, template.spell_id3, template.spell_id4], &positive?/1)

    spell_list = load_spell_list(template.spell_list_id)

    spellbook =
      SpellLoader.build_spellbook(
        template_spell_ids ++ Enum.map(spell_list, & &1.spell_id) ++ script_cast_spell_ids(creature)
      )

    creature
    |> Map.put(:spellbook, spellbook)
    |> Map.put(:spell_list, Enum.filter(spell_list, &Map.has_key?(spellbook, &1.spell_id)))
  end

  defp load_spells(%Mangos.Creature{} = creature) do
    creature
    |> Map.put(:spellbook, %{})
    |> Map.put(:spell_list, [])
  end

  defp load_spell_list(list_id) when is_integer(list_id) and list_id > 0 do
    case Mangos.Repo.get(Mangos.CreatureSpells, list_id) do
      %Mangos.CreatureSpells{} = row ->
        row
        |> Mangos.CreatureSpells.slots()
        |> Enum.map(&CreatureSpell.build/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp load_spell_list(_list_id), do: []

  defp load_addon_auras(nil), do: nil

  defp load_addon_auras(%Mangos.Creature{} = creature) do
    spells =
      creature
      |> addon_aura_ids()
      |> SpellLoader.build_spellbook()
      |> Map.values()

    Map.put(creature, :addon_auras, spells)
  end

  defp addon_aura_ids(%Mangos.Creature{guid: guid, creature_template: %Mangos.CreatureTemplate{auras: template_auras}}) do
    guid
    |> addon_or_template_aura_ids(template_auras)
    |> Enum.uniq()
  end

  defp addon_or_template_aura_ids(guid, template_auras) do
    case Mangos.Repo.get(Mangos.CreatureAddon, guid) do
      %Mangos.CreatureAddon{auras: auras} = row when is_binary(auras) and auras != "" ->
        Mangos.CreatureAddon.aura_ids(row)

      _ ->
        AddonAuras.parse(template_auras)
    end
  end

  defp load_ai_events(nil), do: nil

  defp load_ai_events(%Mangos.Creature{id: entry} = creature) do
    event_rows =
      entry
      |> Mangos.CreatureAiEvent.query()
      |> Mangos.Repo.all()

    scripts_by_id =
      event_rows
      |> Enum.flat_map(&Mangos.CreatureAiEvent.action_script_ids/1)
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureAiScript, &1))

    ai_events =
      event_rows
      |> Enum.map(&AIEvent.build(&1, scripts_by_id))
      |> Enum.reject(&(&1.actions == []))

    Map.put(creature, :ai_events, ai_events)
  end

  defp load_movement_scripts(nil), do: nil

  defp load_movement_scripts(%Mangos.Creature{creature_movement: movement} = creature) when is_list(movement) do
    scripts_by_id =
      movement
      |> Enum.map(& &1.script_id)
      |> Enum.filter(&positive?/1)
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureMovementScript, &1))

    Map.put(creature, :movement_scripts, scripts_by_id)
  end

  defp load_movement_scripts(%Mangos.Creature{} = creature) do
    Map.put(creature, :movement_scripts, %{})
  end

  defp script_cast_spell_ids(%Mangos.Creature{} = creature) do
    event_steps = creature |> Map.get(:ai_events, []) |> Enum.flat_map(& &1.actions)
    movement_steps = creature |> Map.get(:movement_scripts, %{}) |> Map.values()

    (event_steps ++ movement_steps)
    |> Enum.flat_map(fn steps -> Enum.map(steps, &ScriptStep.cast_spell_id/1) end)
    |> Enum.filter(&positive?/1)
    |> Enum.uniq()
  end

  defp load_creature_movement(nil), do: nil

  defp load_creature_movement(%Mangos.Creature{} = creature) do
    creature_movement =
      Mangos.CreatureMovement.query(creature.guid)
      |> Mangos.Repo.all()

    Map.put(creature, :creature_movement, creature_movement)
  end

  defp display_scale(display_id) do
    with %CreatureDisplayInfo{model: model_id, creature_model_scale: display_scale}
         when is_integer(model_id) and is_number(display_scale) <-
           DBC.get(CreatureDisplayInfo, display_id),
         %CreatureModelData{model_scale: model_scale} when is_number(model_scale) <-
           DBC.get(CreatureModelData, model_id) do
      display_scale * model_scale
    else
      _ -> nil
    end
  end

  defp load_equip_items(nil), do: nil

  defp load_equip_items(
         %Mangos.Creature{creature_template: %Mangos.CreatureTemplate{equipment_template_id: id}} = creature
       )
       when is_integer(id) and id > 0 do
    items =
      id
      |> Mangos.CreatureEquipTemplate.query()
      |> Mangos.Repo.all()
      |> select_equipment()
      |> case do
        %Mangos.CreatureEquipTemplate{item1: i1, item2: i2, item3: i3} ->
          Enum.map([i1, i2, i3], &item_template/1)

        nil ->
          [nil, nil, nil]
      end

    Map.put(creature, :equip_items, items)
  end

  defp load_equip_items(%Mangos.Creature{} = creature) do
    Map.put(creature, :equip_items, [nil, nil, nil])
  end

  defp item_template(entry) when is_integer(entry) and entry > 0 do
    Mangos.Repo.get(Mangos.ItemTemplate, entry)
  end

  defp item_template(_entry), do: nil

  defp template_pool(%Mangos.Creature{} = creature) do
    [creature.id, creature.id2, creature.id3, creature.id4, creature.id5]
    |> Enum.filter(&positive?/1)
  end

  defp select_display(%Mangos.CreatureTemplate{} = template) do
    entries =
      [
        {template.model_id1, template.display_scale1, template.display_probability1},
        {template.model_id2, template.display_scale2, template.display_probability2},
        {template.model_id3, template.display_scale3, template.display_probability3},
        {template.model_id4, template.display_scale4, template.display_probability4}
      ]
      |> Enum.filter(fn {display_id, _scale, _probability} -> positive?(display_id) end)

    case weighted_pick(entries, fn {_display_id, _scale, probability} -> probability end) do
      {display_id, scale, _probability} -> {display_id, positive_scale(scale)}
      nil -> {0, nil}
    end
  end

  defp select_equipment([]), do: nil
  defp select_equipment(rows), do: weighted_pick(rows, & &1.probability)

  defp weighted_pick([], _weight_fun), do: nil

  defp weighted_pick(entries, weight_fun) do
    total = Enum.reduce(entries, 0, fn entry, acc -> acc + max(weight_fun.(entry) || 0, 0) end)
    pick_weighted(entries, weight_fun, total)
  end

  defp pick_weighted(entries, weight_fun, total) when total > 0 do
    roll = :rand.uniform(total)

    Enum.reduce_while(entries, 0, fn entry, acc ->
      acc = acc + max(weight_fun.(entry) || 0, 0)
      if roll <= acc, do: {:halt, entry}, else: {:cont, acc}
    end)
  end

  defp pick_weighted(entries, _weight_fun, _total), do: Enum.random(entries)

  defp positive?(value), do: is_integer(value) and value > 0

  defp positive_scale(scale) when is_number(scale) and scale > 0, do: scale
  defp positive_scale(_scale), do: nil

  defp start(%Mangos.Creature{} = creature) do
    creature
    |> Mob.build()
    |> start_mob()
  end

  def start_mob(%Mob{} = mob) do
    Metadata.put(
      mob.object.guid,
      %{
        name: mob.internal.name,
        bounding_radius: mob.unit.bounding_radius,
        combat_reach: mob.unit.combat_reach,
        level: mob.unit.level,
        unit_flags: mob.unit.flags,
        detection_range: mob.internal.creature.detection_range,
        display_id: mob.unit.display_id,
        attacker_count: 0,
        alive?: mob.unit.health > 0,
        health_pct: Core.health_pct(mob)
      }
      |> Map.merge(Mob.visibility_metadata(mob))
      |> Map.merge(FactionLoader.metadata(mob.unit.faction_template))
    )

    World.start_entity(mob)
  end
end
