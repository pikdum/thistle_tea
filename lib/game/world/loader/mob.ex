defmodule ThistleTea.Game.World.Loader.Mob do
  @moduledoc """
  Loads the creature spawns for a cell from Mangos (with templates, movement,
  and display info) into mob entity structs.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.Creature.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.map(&load_creature/1)
    |> Enum.each(&start/1)
  end

  def load_creature(%Mangos.Creature{} = creature) do
    creature
    |> load_creature_movement()
    |> load_creature_model_info()
    |> load_display_scale()
    |> load_equip_items()
    |> load_spells()
    |> load_addon_auras()
  end

  defp load_spells(%Mangos.Creature{creature_template: %Mangos.CreatureTemplate{} = template} = creature) do
    template_spell_ids =
      case Mangos.Repo.get(Mangos.CreatureTemplateSpells, template.entry) do
        %Mangos.CreatureTemplateSpells{} = row -> Mangos.CreatureTemplateSpells.spell_ids(row)
        _ -> []
      end

    spell_list = load_spell_list(template.spell_list_id)
    spellbook = SpellLoader.build_spellbook(template_spell_ids ++ Enum.map(spell_list, & &1.spell_id))

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

  defp load_addon_auras(%Mangos.Creature{} = creature) do
    spells =
      creature
      |> addon_aura_ids()
      |> SpellLoader.build_spellbook()
      |> Map.values()

    Map.put(creature, :addon_auras, spells)
  end

  defp addon_aura_ids(%Mangos.Creature{guid: guid, id: entry}) do
    case Mangos.Repo.get(Mangos.CreatureAddon, guid) do
      %Mangos.CreatureAddon{auras: auras} = row when is_binary(auras) and auras != "" ->
        Mangos.CreatureAddon.aura_ids(row)

      _ ->
        Mangos.CreatureTemplateAddon.aura_ids(Mangos.Repo.get(Mangos.CreatureTemplateAddon, entry))
    end
  end

  defp load_creature_movement(%Mangos.Creature{} = creature) do
    creature_movement =
      Mangos.CreatureMovement.query(creature.guid)
      |> Mangos.Repo.all()

    Map.put(creature, :creature_movement, creature_movement)
  end

  defp load_creature_model_info(%Mangos.Creature{modelid: modelid} = creature)
       when is_integer(modelid) and modelid > 0 do
    Map.put(creature, :creature_model_info, Mangos.Repo.get(Mangos.CreatureModelInfo, modelid))
  end

  defp load_creature_model_info(%Mangos.Creature{} = creature) do
    Map.put(creature, :creature_model_info, nil)
  end

  defp load_display_scale(%Mangos.Creature{modelid: modelid} = creature) when is_integer(modelid) and modelid > 0 do
    Map.put(creature, :display_scale, display_scale(modelid))
  end

  defp load_display_scale(%Mangos.Creature{} = creature) do
    Map.put(creature, :display_scale, nil)
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

  defp load_equip_items(
         %Mangos.Creature{creature_template: %Mangos.CreatureTemplate{equipment_template_id: id}} = creature
       )
       when is_integer(id) and id > 0 do
    items =
      case Mangos.Repo.get(Mangos.CreatureEquipTemplate, id) do
        %Mangos.CreatureEquipTemplate{equipentry1: e1, equipentry2: e2, equipentry3: e3} ->
          Enum.map([e1, e2, e3], &creature_item_template/1)

        nil ->
          [nil, nil, nil]
      end

    Map.put(creature, :equip_items, items)
  end

  defp load_equip_items(%Mangos.Creature{} = creature) do
    Map.put(creature, :equip_items, [nil, nil, nil])
  end

  defp creature_item_template(entry) when is_integer(entry) and entry > 0 do
    Mangos.Repo.get(Mangos.CreatureItemTemplate, entry)
  end

  defp creature_item_template(_entry), do: nil

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
        display_id: mob.unit.display_id,
        attacker_count: 0,
        alive?: mob.unit.health > 0
      }
      |> Map.merge(Mob.visibility_metadata(mob))
      |> Map.merge(FactionLoader.metadata(mob.unit.faction_template))
    )

    World.start_entity(mob)
  end
end
