defmodule ThistleTea.Game.World.Loader.Battleground do
  @moduledoc """
  ETS catalog of VMangos battleground admission and event-spawn data.
  """

  import Ecto.Query

  alias ThistleTea.DB.Mangos
  alias ThistleTea.DBC
  alias ThistleTea.Game.Battleground
  alias ThistleTea.Game.Battleground.Template

  @supported_patch 10
  @table_options [:named_table, :public, read_concurrency: true]
  @warsong_broadcast_text_ids [
    9_801,
    9_802,
    9_803,
    9_804,
    9_805,
    9_806,
    9_807,
    9_808,
    9_809,
    9_842,
    9_843,
    10_014,
    10_015,
    10_016,
    10_022,
    10_023
  ]

  def init(table \\ __MODULE__) do
    case :ets.whereis(table) do
      :undefined -> :ets.new(table, @table_options)
      _table_id -> table
    end
  end

  def load_all do
    templates = Mangos.Repo.all(from(row in Mangos.BattlegroundTemplate, where: row.patch <= @supported_patch))
    battlemasters = Mangos.Repo.all(Mangos.BattlemasterEntry)
    safe_locs = load_safe_locs(templates)
    event_members = load_event_members(Battleground.warsong_gulch_map())
    load(templates, safe_locs, battlemasters, event_members)
  end

  def load(templates, safe_locs, battlemasters, event_members, table \\ __MODULE__) do
    templates =
      templates
      |> Enum.group_by(& &1.id)
      |> Map.new(fn {type_id, versions} ->
        row = Enum.max_by(versions, & &1.patch)
        {type_id, template(row, safe_locs)}
      end)

    Enum.each(templates, fn {type_id, template} ->
      :ets.insert(table, {{:type, type_id}, template})
      :ets.insert(table, {{:map, template.map_id}, template})
    end)

    Enum.each(battlemasters, fn row ->
      if Map.has_key?(templates, row.bg_template) do
        :ets.insert(table, {{:battlemaster, row.entry}, row.bg_template})
      end
    end)

    Enum.each(event_members, fn member ->
      :ets.insert(
        table,
        {{:event_member, member.map, member.event1, member.event2, member.kind, member.db_guid}, member}
      )
    end)

    :ets.insert(table, {:loaded, true})
    :ok
  end

  def template_for_map(map_id, table \\ __MODULE__) when is_integer(map_id) do
    lookup(table, {:map, map_id})
  end

  def template_for_type(type_id, table \\ __MODULE__) when is_integer(type_id) do
    lookup(table, {:type, type_id})
  end

  def template_for_battlemaster(entry, table \\ __MODULE__) when is_integer(entry) do
    case lookup(table, {:battlemaster, entry}) do
      type_id when is_integer(type_id) -> template_for_type(type_id, table)
      _missing -> nil
    end
  end

  def battlemaster?(entry, table \\ __MODULE__), do: not is_nil(template_for_battlemaster(entry, table))

  def event_members(map_id, event1, table \\ __MODULE__) do
    :ets.match_object(table, {{:event_member, map_id, event1, :_, :_, :_}, :_})
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(&{&1.kind, &1.db_guid})
  end

  def base_flag_db_guid(team, table \\ __MODULE__)
  def base_flag_db_guid(:alliance, table), do: first_game_object_guid(0, table)
  def base_flag_db_guid(:horde, table), do: first_game_object_guid(1, table)

  def gate_entries(table \\ __MODULE__) do
    Battleground.warsong_gulch_map()
    |> event_members(254, table)
    |> Enum.map(& &1.entry)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def ghost_gate_db_guids(table \\ __MODULE__) do
    Battleground.warsong_gulch_map()
    |> event_members(253, table)
    |> Enum.filter(&(&1.kind == :game_object))
    |> Enum.map(& &1.db_guid)
    |> Enum.sort()
  end

  def ghost_gate_entries(table \\ __MODULE__) do
    Battleground.warsong_gulch_map()
    |> event_members(253, table)
    |> Enum.filter(&(&1.kind == :game_object))
    |> Enum.map(& &1.entry)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def spirit_guide_entries(table \\ __MODULE__) do
    Battleground.warsong_gulch_map()
    |> event_members(2, table)
    |> Enum.filter(&(&1.kind == :creature))
    |> Enum.map(& &1.entry)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def broadcast_text_ids, do: @warsong_broadcast_text_ids

  defp template(row, safe_locs) do
    %Template{
      type_id: row.id,
      map_id: map_id(row.id),
      min_players_per_team: row.min_players_per_team,
      max_players_per_team: row.max_players_per_team,
      min_level: row.min_level,
      max_level: row.max_level,
      alliance_start: safe_location(safe_locs, row.alliance_start_location),
      horde_start: safe_location(safe_locs, row.horde_start_location),
      alliance_graveyard: graveyard(safe_locs, :alliance, row.id),
      horde_graveyard: graveyard(safe_locs, :horde, row.id),
      alliance_win_spell: row.alliance_win_spell,
      alliance_lose_spell: row.alliance_lose_spell,
      horde_win_spell: row.horde_win_spell,
      horde_lose_spell: row.horde_lose_spell
    }
  end

  defp map_id(1), do: 30
  defp map_id(2), do: Battleground.warsong_gulch_map()
  defp map_id(3), do: 529

  defp safe_location(safe_locs, id) do
    case Map.get(safe_locs, id) do
      %{location_x: x, location_y: y, location_z: z} -> {x, y, z, 0.0}
      _missing -> nil
    end
  end

  defp load_safe_locs(templates) do
    ids =
      templates
      |> Enum.flat_map(&[&1.alliance_start_location, &1.horde_start_location])
      |> Kernel.++([771, 772])
      |> Enum.uniq()

    DBC.all(from(loc in WorldSafeLocs, where: loc.id in ^ids))
    |> Map.new(&{&1.id, &1})
  end

  defp graveyard(safe_locs, :alliance, 2), do: safe_location(safe_locs, 771)
  defp graveyard(safe_locs, :horde, 2), do: safe_location(safe_locs, 772)
  defp graveyard(_safe_locs, _team, _type_id), do: nil

  defp load_event_members(map_id) do
    game_objects =
      Mangos.Repo.all(
        from(bg in Mangos.GameObjectBattleground,
          join: object in Mangos.GameObject,
          on: object.guid == bg.guid,
          where: object.map == ^map_id,
          select: %{
            map: object.map,
            event1: bg.event1,
            event2: bg.event2,
            kind: :game_object,
            db_guid: object.guid,
            entry: object.id
          }
        )
      )

    creatures =
      Mangos.Repo.all(
        from(bg in Mangos.CreatureBattleground,
          join: creature in Mangos.Creature,
          on: creature.guid == bg.guid,
          where: creature.map == ^map_id,
          select: %{
            map: creature.map,
            event1: bg.event1,
            event2: bg.event2,
            kind: :creature,
            db_guid: creature.guid,
            entry: creature.id
          }
        )
      )

    game_objects ++ creatures
  end

  defp first_game_object_guid(event1, table) do
    Battleground.warsong_gulch_map()
    |> event_members(event1, table)
    |> Enum.find_value(fn
      %{kind: :game_object, db_guid: guid} -> guid
      _member -> nil
    end)
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _missing -> nil
    end
  end
end
