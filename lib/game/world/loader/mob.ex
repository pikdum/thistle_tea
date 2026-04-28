defmodule ThistleTea.Game.World.Loader.Mob do
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    Mangos.Creature.query_cell(cell, events)
    |> Mangos.Repo.all()
    |> Enum.map(&load_creature_movement/1)
    |> Enum.map(&load_creature_model_info/1)
    |> Enum.map(&load_equip_items/1)
    |> Enum.each(&start/1)
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
    mob = Mob.build(creature)

    Metadata.put(mob.object.guid, %{
      name: mob.internal.name,
      bounding_radius: mob.unit.bounding_radius,
      combat_reach: mob.unit.combat_reach,
      attacker_count: 0,
      alive?: mob.unit.health > 0
    })

    World.start_entity(mob)
  end
end
