defmodule ThistleTea.Game.World.Loader.Mob do
  @moduledoc """
  Loads creature spawns and their immutable blueprint data from the VMangos seed.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Entity.Server.Mob.Incarnation
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.CreatureGroup, as: CreatureGroupLoader
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Mob.Batch
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpawnPool
  alias ThistleTea.Game.World.SpawnPool.Catalog
  alias ThistleTea.Game.World.System.GameEvent

  def load(cell) do
    events = GameEvent.get_events()

    creatures =
      cell
      |> Mangos.Creature.query_cell(events)
      |> Mangos.Repo.all()

    creatures = include_formation_members(creatures, events)

    {pooled, singletons} =
      Enum.split_with(creatures, fn creature ->
        match?({:pool, _pool_id}, Catalog.group_for(:creature, creature.guid))
      end)

    pooled
    |> Enum.group_by(&Catalog.group_for(:creature, &1.guid))
    |> Enum.each(fn {group, creatures} ->
      members = Enum.map(creatures, &{:creature, &1.guid})
      :ok = SpawnPool.activate(group, cell, nil, members)
    end)

    singletons
    |> Batch.load()
    |> Enum.each(fn creature ->
      group = Catalog.group_for(:creature, creature.guid)
      :ok = SpawnPool.activate(group, cell, Mob.build(creature))
    end)
  end

  defp include_formation_members([], _events), do: []

  defp include_formation_members([%Mangos.Creature{map: map} | _] = creatures, events) do
    ids = Enum.map(creatures, & &1.guid)
    missing = CreatureGroupLoader.formation_members(map, ids) -- ids

    if missing == [] do
      creatures
    else
      creatures ++ (missing |> Mangos.Creature.query_guids(events) |> Mangos.Repo.all())
    end
  end

  def blueprints(guids, events \\ GameEvent.get_events()) when is_list(guids) do
    Mangos.Creature.query_guids(guids, events)
    |> Mangos.Repo.all()
    |> Batch.load()
    |> Map.new(fn creature -> {{:creature, creature.guid}, Mob.build(creature)} end)
  end

  def load_creature(%Mangos.Creature{} = creature), do: Batch.load_one(creature)

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
        proximity_aggro?: Mob.proximity_aggro?(mob),
        detection_range: mob.internal.creature.detection_range,
        display_id: mob.unit.display_id,
        attacker_count: 0,
        incarnation_id: Incarnation.id(mob),
        alive?: mob.unit.health > 0,
        feigning_death?: FeignDeath.successful?(mob),
        victim_guid: mob.unit.target,
        detect_range_modifier: Aura.flat_amount(mob, :mod_detect_range),
        in_combat: false,
        rooted?: mob.internal.rooted? == true,
        root_aura?: Aura.has_aura?(mob, :mod_root),
        health_pct: Core.health_pct(mob),
        health_deficit: Core.health_deficit(mob),
        mana_pct: Core.mana_pct(mob),
        power_type: mob.unit.power_type,
        shapeshift_form: mob.unit.shapeshift_form || 0,
        orientation: elem(mob.movement_block.position, 3),
        aura_sources: Aura.source_spells(mob),
        aura_stacks: Aura.spell_stacks(mob),
        crowd_controlled?: Aura.crowd_controlled?(mob),
        dispel_options: Aura.dispel_options(mob),
        mechanic_resistance: Aura.misc_amounts(mob, :mechanic_resistance),
        school_resistances: SpellResist.school_resistances(mob),
        attacker_spell_hit_chance: Aura.attacker_spell_hit_chance(mob)
      }
      |> Map.merge(Mob.visibility_metadata(mob))
      |> Map.merge(pet_metadata(mob))
      |> Map.merge(FactionLoader.metadata(mob.unit.faction_template))
    )
  end

  defp pet_metadata(%Mob{internal: %{pet: %{owner_guid: owner_guid, profile: profile}}} = mob) do
    %{
      owner_guid: owner_guid,
      pet_profile: profile,
      pet_number: mob.unit.pet_number,
      pet_name_timestamp: mob.unit.pet_name_timestamp
    }
  end

  defp pet_metadata(%Mob{}), do: %{}
end
