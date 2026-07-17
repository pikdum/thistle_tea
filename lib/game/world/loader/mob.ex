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
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Server.Mob.Incarnation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Condition, as: ConditionLoader
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.Catalog
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.Creature.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.each(&activate(&1, cell))
  end

  def blueprints(guids, events \\ GameEvent.get_events()) when is_list(guids) do
    Mangos.Creature.query_guids(guids, events)
    |> Mangos.Repo.all()
    |> Enum.map(&load_creature/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn creature -> {{:creature, creature.guid}, creature |> Mob.build()} end)
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
    |> load_conditions()
    |> load_equip_items()
    |> load_spells()
    |> load_addon_auras()
  end

  defp load_creature_template(%Mangos.Creature{} = creature) do
    entry = creature |> template_pool() |> Enum.random()

    case Mangos.Repo.get(Mangos.CreatureTemplate, entry) do
      %Mangos.CreatureTemplate{} = template ->
        %{creature | id: entry, creature_template: template}

      _ ->
        nil
    end
  end

  defp load_creature_level(nil), do: nil

  defp load_creature_level(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    %{creature | selected_level: Enum.random(template.min_level..template.max_level)}
  end

  defp load_creature_class_level_stats(nil), do: nil

  defp load_creature_class_level_stats(
         %Mangos.Creature{creature_template: %Mangos.CreatureTemplate{unit_class: unit_class}} = creature
       ) do
    %{creature | creature_class_level_stats: Mangos.CreatureClassLevelStats.get(unit_class, creature.selected_level)}
  end

  defp load_display(nil), do: nil

  defp load_display(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    {display_id, display_scale} = select_display(template)

    %{
      creature
      | modelid: display_id,
        display_scale: display_scale || display_scale(display_id),
        creature_display_info_addon: Mangos.CreatureDisplayInfoAddon.get(display_id)
    }
  end

  defp load_spells(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    template_spell_ids =
      Enum.filter([template.spell_id1, template.spell_id2, template.spell_id3, template.spell_id4], &positive?/1)

    spell_list = load_spell_list(template.spell_list_id)
    intrinsic_spells = intrinsic_spells(template)

    spellbook =
      SpellLoader.build_spellbook(
        template_spell_ids ++
          Enum.map(spell_list, & &1.spell_id) ++
          Enum.map(intrinsic_spells, & &1.spell_id) ++ script_cast_spell_ids(creature)
      )

    spells = Enum.filter(spell_list ++ intrinsic_spells, &Map.has_key?(spellbook, &1.spell_id))
    %{creature | spellbook: spellbook, spell_list: spells}
  end

  defp load_spells(%Mangos.Creature{} = creature) do
    %{creature | spellbook: %{}, spell_list: []}
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

  defp intrinsic_spells(%Mangos.CreatureTemplate{} = template) do
    [intrinsic_spell(template.spawn_spell_id, :self), intrinsic_totem_spell(template.totem_spell_id)]
    |> Enum.reject(&is_nil/1)
  end

  defp intrinsic_totem_spell(spell_id) when is_integer(spell_id) and spell_id > 0 do
    cast_target =
      case SpellLoader.load(spell_id) do
        %Spell{} = spell -> if Spell.requires_hostile_target?(spell), do: :victim, else: :self
        _ -> :self
      end

    intrinsic_spell(spell_id, cast_target)
  end

  defp intrinsic_totem_spell(_spell_id), do: nil

  defp intrinsic_spell(spell_id, cast_target) when is_integer(spell_id) and spell_id > 0 do
    %CreatureSpell{
      spell_id: spell_id,
      cast_target: cast_target,
      cast_flags: MapSet.new([:triggered]),
      delay_repeat_min_ms: 2_000,
      delay_repeat_max_ms: 2_000
    }
  end

  defp intrinsic_spell(_spell_id, _cast_target), do: nil

  defp load_addon_auras(%Mangos.Creature{} = creature) do
    spells =
      creature
      |> addon_aura_ids()
      |> SpellLoader.build_spellbook()
      |> Map.values()

    %{creature | addon_auras: spells}
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

    %{creature | ai_events: ai_events}
  end

  defp load_conditions(nil), do: nil

  defp load_conditions(%Mangos.Creature{} = creature) do
    ai_events = creature.ai_events
    movement_scripts = creature.movement_scripts

    condition_ids =
      Enum.map(ai_events, & &1.condition_id) ++
        Enum.map(all_steps(ai_events, movement_scripts), & &1.condition_id)

    case ConditionLoader.load_by_ids(condition_ids) do
      conditions when map_size(conditions) == 0 ->
        creature

      conditions ->
        %{
          creature
          | ai_events: Enum.map(ai_events, &attach_event_condition(&1, conditions)),
            movement_scripts: attach_script_conditions(movement_scripts, conditions)
        }
    end
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

  defp load_movement_scripts(nil), do: nil

  defp load_movement_scripts(%Mangos.Creature{creature_movement: movement} = creature) when is_list(movement) do
    scripts_by_id =
      movement
      |> Enum.map(& &1.script_id)
      |> Enum.filter(&positive?/1)
      |> then(&ScriptLoader.load_by_ids(Mangos.CreatureMovementScript, &1))

    %{creature | movement_scripts: scripts_by_id}
  end

  defp load_movement_scripts(%Mangos.Creature{} = creature) do
    %{creature | movement_scripts: %{}}
  end

  defp script_cast_spell_ids(%Mangos.Creature{} = creature) do
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

  defp load_creature_movement(nil), do: nil

  defp load_creature_movement(%Mangos.Creature{} = creature) do
    creature_movement =
      Mangos.CreatureMovement.query(creature.guid)
      |> Mangos.Repo.all()

    %{creature | creature_movement: creature_movement}
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

    %{creature | equip_items: items}
  end

  defp load_equip_items(%Mangos.Creature{} = creature) do
    %{creature | equip_items: [nil, nil, nil]}
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

  defp activate(%Mangos.Creature{} = creature, cell) do
    case Catalog.group_for(:creature, creature.guid) do
      {:pool, _pool_id} = group ->
        SpawnPool.activate(group, cell)

      {:singleton, :creature, _guid} = group ->
        loaded = load_creature(creature)
        SpawnPool.activate(group, cell, Mob.build(loaded))
    end
  end

  def start_mob(%Mob{} = mob) do
    mob = Incarnation.ensure(mob)
    put_metadata(mob)
    World.start_entity(mob)
  end

  def start_pool_mob(%Mob{} = mob) do
    mob = Incarnation.ensure(mob)
    put_metadata(mob)
    World.start_incarnation(mob)
  end

  defp put_metadata(%Mob{} = mob) do
    Metadata.put(
      mob.object.guid,
      %{
        name: mob.internal.name,
        bounding_radius: mob.unit.bounding_radius,
        combat_reach: mob.unit.combat_reach,
        level: mob.unit.level,
        tameable?: Bitwise.band(mob.internal.creature.type_flags || 0, 0x1) != 0,
        unit_flags: mob.unit.flags,
        detection_range: mob.internal.creature.detection_range,
        display_id: mob.unit.display_id,
        attacker_count: 0,
        incarnation_id: Incarnation.id(mob),
        alive?: mob.unit.health > 0,
        health_pct: Core.health_pct(mob),
        orientation: elem(mob.movement_block.position, 3),
        aura_sources: Aura.source_spells(mob)
      }
      |> Map.merge(Mob.visibility_metadata(mob))
      |> Map.merge(pet_metadata(mob))
      |> Map.merge(FactionLoader.metadata(mob.unit.faction_template))
    )
  end

  defp pet_metadata(%Mob{internal: %{pet: %{owner_guid: owner_guid, profile: profile}}}) do
    %{owner_guid: owner_guid, pet_profile: profile}
  end

  defp pet_metadata(%Mob{}), do: %{}
end
