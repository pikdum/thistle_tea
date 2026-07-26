defmodule ThistleTea.Game.World.Loader.Mob.Batch do
  @moduledoc """
  Batch-loads immutable VMangos and DBC data needed to build mob blueprints.
  """
  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DB.Mangos.AddonAuras
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def load([]), do: []

  def load(creatures) when is_list(creatures) do
    creatures
    |> select_template_entries()
    |> attach_templates()
    |> select_levels_and_displays()
    |> attach_class_level_stats()
    |> attach_display_data()
    |> attach_movement()
    |> attach_ai()
    |> attach_conditions()
    |> attach_equipment()
    |> attach_spells()
  end

  def load_one(%Mangos.Creature{} = creature) do
    [creature]
    |> load()
    |> List.first()
  end

  defp select_template_entries(creatures) do
    Enum.map(creatures, fn creature ->
      %{creature | id: creature |> template_pool() |> Enum.random()}
    end)
  end

  defp attach_templates(creatures) do
    templates =
      creatures
      |> Enum.map(& &1.id)
      |> fetch_by_ids(Mangos.CreatureTemplate, :entry)

    creatures
    |> Enum.map(fn creature ->
      case Map.get(templates, creature.id) do
        %Mangos.CreatureTemplate{} = template -> %{creature | creature_template: template}
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp select_levels_and_displays(creatures) do
    Enum.map(creatures, fn %Mangos.Creature{creature_template: template} = creature ->
      {display_id, display_scale} = select_display(template)

      %{
        creature
        | selected_level: Enum.random(template.min_level..template.max_level),
          modelid: display_id,
          display_scale: display_scale
      }
    end)
  end

  defp attach_class_level_stats(creatures) do
    classes = creatures |> Enum.map(& &1.creature_template.unit_class) |> Enum.uniq()
    levels = creatures |> Enum.map(& &1.selected_level) |> Enum.uniq()

    stats =
      Mangos.Repo.all(
        from(row in Mangos.CreatureClassLevelStats,
          where: row.class in ^classes and row.level in ^levels
        )
      )
      |> Map.new(fn row -> {{row.class, row.level}, row} end)

    Enum.map(creatures, fn creature ->
      key = {creature.creature_template.unit_class, creature.selected_level}
      %{creature | creature_class_level_stats: Map.get(stats, key)}
    end)
  end

  defp attach_display_data(creatures) do
    display_ids = creatures |> Enum.map(& &1.modelid) |> Enum.filter(&positive?/1) |> Enum.uniq()

    addons =
      Mangos.Repo.all(
        from(row in Mangos.CreatureDisplayInfoAddon,
          where: row.display_id in ^display_ids,
          order_by: [asc: row.display_id, desc: row.build]
        )
      )
      |> Enum.reduce(%{}, fn row, acc -> Map.put_new(acc, row.display_id, row) end)

    scales = display_scales(display_ids)

    Enum.map(creatures, fn creature ->
      scale = positive_scale(creature.display_scale) || Map.get(scales, creature.modelid)

      %{
        creature
        | display_scale: scale,
          creature_display_info_addon: Map.get(addons, creature.modelid)
      }
    end)
  end

  defp display_scales(display_ids) do
    display_rows =
      DBC.all(from(row in CreatureDisplayInfo, where: row.id in ^display_ids))

    model_ids = display_rows |> Enum.map(& &1.model) |> Enum.filter(&positive?/1) |> Enum.uniq()

    models =
      DBC.all(from(row in CreatureModelData, where: row.id in ^model_ids))
      |> Map.new(&{&1.id, &1})

    Map.new(display_rows, fn display ->
      scale =
        with %CreatureModelData{model_scale: model_scale} when is_number(model_scale) <-
               Map.get(models, display.model),
             display_scale when is_number(display_scale) <- display.creature_model_scale do
          display_scale * model_scale
        else
          _ -> nil
        end

      {display.id, scale}
    end)
  end

  defp attach_movement(creatures) do
    guids = Enum.map(creatures, & &1.guid)

    movements =
      Mangos.Repo.all(
        from(row in Mangos.CreatureMovement,
          where: row.id in ^guids,
          order_by: [row.id, row.point]
        )
      )
      |> Enum.group_by(& &1.id)

    scripts =
      movements
      |> Map.values()
      |> List.flatten()
      |> Enum.map(& &1.script_id)
      |> Enum.filter(&positive?/1)
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureMovementScript, &1))

    Enum.map(creatures, fn creature ->
      movement = Map.get(movements, creature.guid, [])
      script_ids = movement |> Enum.map(& &1.script_id) |> Enum.filter(&positive?/1) |> Enum.uniq()

      %{
        creature
        | creature_movement: movement,
          movement_scripts: Map.take(scripts, script_ids)
      }
    end)
  end

  defp attach_ai(creatures) do
    entries = creatures |> Enum.map(& &1.id) |> Enum.uniq()

    event_rows =
      Mangos.Repo.all(
        from(row in Mangos.CreatureAiEvent,
          where: row.creature_id in ^entries,
          order_by: [row.creature_id, row.id]
        )
      )

    scripts =
      event_rows
      |> Enum.flat_map(&Mangos.CreatureAiEvent.action_script_ids/1)
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureAiScript, &1))

    events =
      event_rows
      |> Enum.group_by(& &1.creature_id)
      |> Map.new(fn {entry, rows} ->
        built =
          rows
          |> Enum.map(&AIEvent.build(&1, scripts))
          |> Enum.reject(&(&1.actions == []))

        {entry, built}
      end)

    Enum.map(creatures, fn creature ->
      %{creature | ai_events: Map.get(events, creature.id, [])}
    end)
  end

  defp attach_conditions(creatures) do
    condition_ids =
      Enum.flat_map(creatures, fn creature ->
        Enum.map(creature.ai_events, & &1.condition_id) ++
          Enum.map(all_steps(creature.ai_events, creature.movement_scripts), & &1.condition_id)
      end)

    conditions = ConditionLoader.load_by_ids(condition_ids)

    Enum.map(creatures, fn creature ->
      %{
        creature
        | ai_events: Enum.map(creature.ai_events, &attach_event_condition(&1, conditions)),
          movement_scripts: attach_script_conditions(creature.movement_scripts, conditions)
      }
    end)
  end

  defp all_steps(ai_events, movement_scripts) do
    direct =
      Enum.flat_map(ai_events, fn event -> List.flatten(event.actions) end) ++
        List.flatten(Map.values(movement_scripts))

    Enum.flat_map(direct, &with_sub_steps/1)
  end

  defp with_sub_steps(%ScriptStep{} = step) do
    [step | step.sub_scripts |> Map.values() |> List.flatten() |> Enum.flat_map(&with_sub_steps/1)]
  end

  defp attach_event_condition(%AIEvent{} = event, conditions) do
    actions = Enum.map(event.actions, fn steps -> Enum.map(steps, &attach_step_condition(&1, conditions)) end)
    %{event | condition: Map.get(conditions, event.condition_id), actions: actions}
  end

  defp attach_script_conditions(movement_scripts, conditions) do
    Map.new(movement_scripts, fn {script_id, steps} ->
      {script_id, Enum.map(steps, &attach_step_condition(&1, conditions))}
    end)
  end

  defp attach_step_condition(%ScriptStep{} = step, conditions) do
    sub_scripts =
      Map.new(step.sub_scripts, fn {script_id, steps} ->
        {script_id, Enum.map(steps, &attach_step_condition(&1, conditions))}
      end)

    %{step | condition: Map.get(conditions, step.condition_id), sub_scripts: sub_scripts}
  end

  defp attach_equipment(creatures) do
    equipment_ids =
      creatures
      |> Enum.map(& &1.creature_template.equipment_template_id)
      |> Enum.filter(&positive?/1)
      |> Enum.uniq()

    equipment =
      Mangos.Repo.all(
        from(row in Mangos.CreatureEquipTemplate,
          where: row.entry in ^equipment_ids
        )
      )
      |> Enum.group_by(& &1.entry)

    selections =
      Map.new(creatures, fn creature ->
        rows = Map.get(equipment, creature.creature_template.equipment_template_id, [])
        {creature.guid, select_equipment(rows)}
      end)

    item_ids =
      selections
      |> Map.values()
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn row -> [row.item1, row.item2, row.item3] end)
      |> Enum.filter(&positive?/1)

    items = fetch_by_ids(item_ids, Mangos.ItemTemplate, :entry)

    Enum.map(creatures, fn creature ->
      equipped =
        case Map.get(selections, creature.guid) do
          %Mangos.CreatureEquipTemplate{} = row ->
            Enum.map([row.item1, row.item2, row.item3], &Map.get(items, &1))

          nil ->
            [nil, nil, nil]
        end

      %{creature | equip_items: equipped}
    end)
  end

  defp attach_spells(creatures) do
    list_ids =
      creatures
      |> Enum.map(& &1.creature_template.spell_list_id)
      |> Enum.filter(&positive?/1)

    lists =
      list_ids
      |> fetch_by_ids(Mangos.CreatureSpells, :entry)
      |> Map.new(fn {entry, row} ->
        spells =
          row
          |> Mangos.CreatureSpells.slots()
          |> Enum.map(&CreatureSpell.build/1)
          |> Enum.reject(&is_nil/1)

        {entry, spells}
      end)

    addons =
      creatures
      |> Enum.map(& &1.guid)
      |> fetch_by_ids(Mangos.CreatureAddon, :guid)

    prepared =
      Enum.map(creatures, fn creature ->
        list = Map.get(lists, creature.creature_template.spell_list_id, [])
        addon_ids = addon_aura_ids(creature, addons)

        %{
          creature: creature,
          list: list,
          addon_ids: addon_ids,
          spell_ids:
            (base_spell_ids(creature, list) ++ addon_ids)
            |> Enum.filter(&positive?/1)
            |> Enum.uniq()
        }
      end)

    spellbook =
      prepared
      |> Enum.flat_map(& &1.spell_ids)
      |> SpellLoader.build_spellbook()

    Enum.map(prepared, &attach_prepared_spells(&1, spellbook))
  end

  defp attach_prepared_spells(prepared, spellbook) do
    creature = prepared.creature
    intrinsic = intrinsic_spells(creature.creature_template, spellbook)

    spell_ids =
      prepared.spell_ids ++
        Enum.map(intrinsic, & &1.spell_id)

    creature_spellbook = Map.take(spellbook, spell_ids)
    spells = Enum.filter(prepared.list ++ intrinsic, &Map.has_key?(creature_spellbook, &1.spell_id))
    addon_auras = prepared.addon_ids |> Enum.map(&Map.get(spellbook, &1)) |> Enum.reject(&is_nil/1)

    %{
      creature
      | spellbook: creature_spellbook,
        spell_list: spells,
        addon_auras: addon_auras
    }
  end

  defp base_spell_ids(creature, list) do
    template = creature.creature_template

    [
      template.spell_id1,
      template.spell_id2,
      template.spell_id3,
      template.spell_id4,
      template.spawn_spell_id,
      template.totem_spell_id
    ] ++
      Enum.map(list, & &1.spell_id) ++
      script_cast_spell_ids(creature)
  end

  defp intrinsic_spells(template, spellbook) do
    [
      intrinsic_spell(template.spawn_spell_id, :self),
      intrinsic_totem_spell(template.totem_spell_id, spellbook)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp intrinsic_totem_spell(spell_id, spellbook) when is_integer(spell_id) and spell_id > 0 do
    {cast_target, cast_flags} =
      case Map.get(spellbook, spell_id) do
        %Spell{} = spell ->
          if Spell.requires_hostile_target?(spell) do
            {:victim, MapSet.new([:triggered])}
          else
            {:self, MapSet.new([:triggered, :aura_not_present])}
          end

        _ ->
          {:self, MapSet.new([:triggered, :aura_not_present])}
      end

    intrinsic_spell(spell_id, cast_target, cast_flags)
  end

  defp intrinsic_totem_spell(_spell_id, _spellbook), do: nil

  defp intrinsic_spell(spell_id, cast_target) when is_integer(spell_id) and spell_id > 0,
    do: intrinsic_spell(spell_id, cast_target, MapSet.new([:triggered]))

  defp intrinsic_spell(_spell_id, _cast_target), do: nil

  defp intrinsic_spell(spell_id, cast_target, cast_flags) do
    %CreatureSpell{
      spell_id: spell_id,
      cast_target: cast_target,
      cast_flags: cast_flags,
      delay_repeat_min_ms: 2_000,
      delay_repeat_max_ms: 2_000
    }
  end

  defp addon_aura_ids(creature, addons) do
    case Map.get(addons, creature.guid) do
      %Mangos.CreatureAddon{auras: auras} = row when is_binary(auras) and auras != "" ->
        Mangos.CreatureAddon.aura_ids(row)

      _ ->
        AddonAuras.parse(creature.creature_template.auras)
    end
    |> Enum.uniq()
  end

  defp script_cast_spell_ids(creature) do
    event_steps = Enum.flat_map(creature.ai_events, & &1.actions)
    movement_steps = Map.values(creature.movement_scripts)

    (event_steps ++ movement_steps)
    |> Enum.flat_map(fn steps -> Enum.flat_map(steps, &locally_run_steps/1) end)
    |> Enum.map(&ScriptStep.cast_spell_id/1)
    |> Enum.filter(&positive?/1)
    |> Enum.uniq()
  end

  defp locally_run_steps(%ScriptStep{command: :start_script} = step) do
    [step | step.sub_scripts |> Map.values() |> List.flatten() |> Enum.flat_map(&locally_run_steps/1)]
  end

  defp locally_run_steps(%ScriptStep{} = step), do: [step]

  defp fetch_by_ids([], _schema, _field), do: %{}

  defp fetch_by_ids(ids, schema, field) do
    ids = Enum.uniq(ids)

    schema
    |> where([row], field(row, ^field) in ^ids)
    |> Mangos.Repo.all()
    |> Map.new(&{Map.fetch!(&1, field), &1})
  end

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
end
