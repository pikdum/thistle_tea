defmodule ThistleTea.Game.World.Loader.Summon do
  @moduledoc """
  ETS cache of fully-loaded creature prototypes for script-driven temporary
  summons, keyed by entry: the first summon of an entry runs the normal mob
  loading pipeline against a synthetic spawn row and caches the result, so
  later summons build without touching the database. Summoned mob guids get
  a session-unique low guid offset far above the seed data's spawn guids.
  """
  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader

  @table_options [:named_table, :public, read_concurrency: true, write_concurrency: :auto]
  @low_guid_base 0x400000

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def build(entry, map, {x, y, z, o}, opts \\ []) when is_integer(entry) and is_list(opts) do
    case template(entry) do
      %Mangos.Creature{} = creature ->
        %{creature | guid: next_low_guid(), map: map, position_x: x, position_y: y, position_z: z, orientation: o}
        |> Mob.build()
        |> Mob.prepare_summon(opts)

      _ ->
        nil
    end
  end

  def build_pet(entry, %{
        object: %{guid: owner_guid},
        unit: owner_unit,
        internal: %{map: map},
        movement_block: %{position: position}
      })
      when is_integer(entry) and is_integer(owner_guid) and is_integer(map) do
    with %Mob{} = mob <- build(entry, map, position),
         level when is_integer(level) <- owner_unit.level do
      stats = pet_stats(entry, level)
      guid = Guid.from_low_guid(:pet, entry, next_low_guid())

      unit =
        mob.unit
        |> apply_pet_stats(stats, level)
        |> then(fn unit ->
          %{
            unit
            | summon: 0,
              summoned_by: owner_guid,
              created_by: owner_guid,
              faction_template: owner_unit.faction_template,
              pet_number: Guid.low_guid(guid),
              pet_name_timestamp: System.system_time(:second),
              pet_loyalty: 0,
              pet_flags: 0
          }
        end)

      internal = %{
        mob.internal
        | pet: %Pet{owner_guid: owner_guid, profile: :combat},
          spawn: %{mob.internal.spawn | temporary?: true, respawn_delay_ms: nil},
          loot: nil,
          in_combat: false
      }

      %{mob | object: %{mob.object | guid: guid}, unit: unit, internal: internal}
    else
      _ -> nil
    end
  end

  def build_pet(_entry, _owner), do: nil

  defp template(entry) do
    case :ets.lookup(__MODULE__, entry) do
      [{^entry, %Mangos.Creature{} = creature}] -> creature
      _ -> load(entry)
    end
  end

  defp load(entry) do
    creature =
      %Mangos.Creature{
        guid: 0,
        id: entry,
        map: 0,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        orientation: 0.0,
        movement_type: 0
      }
      |> MobLoader.load_creature()

    case creature do
      %Mangos.Creature{} -> :ets.insert(__MODULE__, {entry, creature})
      _ -> nil
    end

    creature
  end

  defp pet_stats(entry, level) do
    key = {:pet_stats, entry, level}

    case :ets.lookup(__MODULE__, key) do
      [{^key, stats}] ->
        stats

      _ ->
        stats = Mangos.Repo.get_by(Mangos.PetLevelStats, entry: entry, level: level)
        :ets.insert(__MODULE__, {key, stats})
        stats
    end
  end

  defp next_low_guid do
    @low_guid_base + :erlang.unique_integer([:positive, :monotonic])
  end

  defp apply_pet_stats(unit, %Mangos.PetLevelStats{} = stats, level) do
    %{
      unit
      | level: level,
        health: stats.health,
        max_health: stats.health,
        power1: stats.mana,
        max_power1: stats.mana,
        normal_resistance: stats.armor,
        base_normal_resistance: stats.armor,
        min_damage: stats.dmg_min,
        max_damage: stats.dmg_max,
        base_min_damage: stats.dmg_min,
        base_max_damage: stats.dmg_max,
        strength: stats.strength,
        agility: stats.agility,
        stamina: stats.stamina,
        intellect: stats.intellect,
        spirit: stats.spirit
    }
  end

  defp apply_pet_stats(unit, _stats, level), do: %{unit | level: level}
end
