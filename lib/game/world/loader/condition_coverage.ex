defmodule ThistleTea.Game.World.Loader.ConditionCoverage do
  @moduledoc """
  Builds a deterministic inventory of VMangos condition consumers and their
  reachable condition trees.
  """

  alias Ecto.Adapters.SQL
  alias ThistleTea.DB.Mangos.Repo

  @condition_columns MapSet.new(["condition_id", "conditionid", "required_condition", "requiredcondition"])
  @combinators [-3, -2, -1]

  @type_names %{
    -3 => :not,
    -2 => :or,
    -1 => :and,
    0 => :none,
    1 => :aura,
    2 => :item,
    3 => :item_equipped,
    4 => :area_id,
    5 => :reputation_rank_min,
    6 => :team,
    7 => :skill,
    8 => :quest_rewarded,
    9 => :quest_taken,
    10 => :argent_dawn_commission_aura,
    11 => :saved_variable,
    12 => :active_game_event,
    13 => :cannot_path_to_victim,
    14 => :race_class,
    15 => :level,
    16 => :source_entry,
    17 => :spell,
    18 => :instance_script,
    19 => :quest_available,
    20 => :nearby_creature,
    21 => :nearby_game_object,
    22 => :quest_none,
    23 => :item_with_bank,
    24 => :content_patch,
    25 => :escort,
    26 => :active_holiday,
    27 => :gender,
    28 => :is_player,
    29 => :skill_below,
    30 => :reputation_rank_max,
    31 => :has_flag,
    32 => :last_waypoint,
    33 => :map_id,
    34 => :instance_data,
    35 => :map_event_data,
    36 => :map_event_active,
    37 => :line_of_sight,
    38 => :distance_to_target,
    39 => :moving,
    40 => :has_pet,
    41 => :health_percent,
    42 => :mana_percent,
    43 => :in_combat,
    44 => :reaction,
    45 => :in_group,
    46 => :alive,
    47 => :map_event_targets,
    48 => :object_spawned,
    49 => :object_loot_state,
    50 => :object_fit_condition,
    51 => :pvp_rank,
    52 => :db_guid,
    53 => :local_time,
    54 => :distance_to_position,
    55 => :object_go_state,
    56 => :nearby_player,
    57 => :creature_group_member,
    58 => :creature_group_dead,
    59 => :area_explored
  }

  @implemented MapSet.new([
                 -3,
                 -2,
                 -1,
                 0,
                 1,
                 2,
                 3,
                 4,
                 5,
                 6,
                 7,
                 8,
                 9,
                 10,
                 12,
                 14,
                 15,
                 16,
                 17,
                 19,
                 22,
                 24,
                 27,
                 28,
                 29,
                 30,
                 33,
                 39,
                 40,
                 41,
                 42,
                 43,
                 44,
                 45,
                 46,
                 48,
                 52,
                 53,
                 55,
                 59
               ])
  @partial MapSet.new([20, 21, 25, 35, 36, 37, 38, 47, 50, 54, 56])

  @partial_dependencies %{
    20 => "scripted-event boundary only",
    21 => "scripted-event boundary only",
    25 => "scripted-event boundary only",
    35 => "scripted-event boundary only",
    36 => "scripted-event boundary only",
    37 => "scripted-event boundary only",
    38 => "scripted-event boundary only",
    47 => "scripted-event target snapshots only",
    50 => "spawned game objects; child capabilities still apply",
    54 => "scripted-event boundary only",
    56 => "scripted-event boundary only"
  }

  @blocked_dependencies %{
    11 => "global saved-variable owner",
    13 => "authoritative path-failure state",
    18 => "instance-script callbacks",
    23 => "bank inventory",
    26 => "holiday projection",
    31 => "typed update-field capability",
    34 => "instance data",
    49 => "authoritative VMangos loot-state owner",
    51 => "authoritative honor rank",
    57 => "creature formation owner",
    58 => "creature formation owner"
  }

  def audit(repo \\ Repo) do
    consumers = discover_consumers(repo)
    rows = condition_rows(repo)
    rows_by_entry = Map.new(rows, &{&1.entry, &1})
    roots_by_consumer = roots_by_consumer(repo, consumers)
    direct_references = Enum.sum(Enum.map(roots_by_consumer, fn {_consumer, roots} -> length(roots) end))
    roots = roots_by_consumer |> Map.values() |> List.flatten() |> MapSet.new()
    {reachable, missing, cycles} = walk_roots(roots, rows_by_entry)

    %{
      consumers: consumers,
      roots_by_consumer: roots_by_consumer,
      direct_references: direct_references,
      root_definitions: MapSet.size(roots),
      reachable: reachable,
      reachable_rows: reachable_rows(reachable, rows_by_entry),
      missing: missing,
      cycles: cycles
    }
  end

  def render(audit) do
    consumer_rows =
      audit.roots_by_consumer
      |> Enum.sort_by(fn {_consumer, roots} -> -length(roots) end)
      |> Enum.map_join("\n", fn {consumer, roots} -> "| `#{consumer}` | #{length(roots)} |" end)

    type_rows =
      audit.reachable_rows
      |> Enum.group_by(& &1.type)
      |> Enum.sort_by(fn {type, rows} -> {-length(rows), type} end)
      |> Enum.map_join("\n", fn {type, rows} ->
        "| #{type} | `#{type_name(type)}` | #{length(rows)} | #{status(type)} | #{dependency(type)} |"
      end)

    missing = format_ids(audit.missing)
    cycles = format_cycles(audit.cycles)
    mapped = Enum.count(audit.reachable_rows, &Map.has_key?(@type_names, &1.type))
    evaluable = Enum.count(audit.reachable_rows, &MapSet.member?(@implemented, &1.type))

    """
    # VMangos condition coverage

    This report is generated from `db/vmangos.sqlite` by
    `mix condition.coverage`. Run `mix condition.coverage --check` to verify it.

    Numeric mapping and end-to-end evaluation are separate measurements. A
    semantic name does not imply that the runtime can collect every fact or that
    every consumer has migrated.

    ## Coverage summary

    - Discovered condition consumer columns: #{length(audit.consumers)}.
    - Direct conditioned rows: #{audit.direct_references}.
    - Distinct direct condition roots: #{audit.root_definitions}.
    - Reachable condition IDs: #{MapSet.size(audit.reachable)}.
    - Reachable definitions with known VMangos numeric mappings: #{mapped}.
    - Reachable definitions handled end to end by the shared evaluator: #{evaluable}.
    - Missing child IDs: #{missing}.
    - Cycles: #{cycles}.

    ## Direct consumers

    | Table and column | Rows |
    | --- | ---: |
    #{consumer_rows}

    ## Reachable condition types

    | ID | Semantic type | Definitions | Runtime status | Missing dependency |
    | ---: | --- | ---: | --- | --- |
    #{type_rows}

    ## Consumer integration

    | Consumer | Integration status | Unknown policy |
    | --- | --- | --- |
    | Gossip menus and options | Shared evaluator; display and selection are revalidated | Deny unknown |
    | EventAI and loaded scripts | Shared evaluator with `AIEnvironment` facts | Deny unknown |
    | Area-trigger teleports | Resolved tree cached with teleport | Deny unknown |
    | Vendors | Typed conditioned rows; purchase revalidated | Deny unknown |
    | Loot | Actor-aware direct items; conditioned references validated before expansion | Deny unknown at view, roll, assignment, reservation, and pre-transfer validation |
    | Quest availability | Condition ID not integrated | Not evaluated |
    | Remaining discovered consumers | Inventory only | Not integrated |

    ## Dependency-ranked backlog

    1. Consumer migrations: quest and remaining discovered consumers.
    2. Partial world facts currently collected only by the scripted-event
       boundary or for spawned game objects.
    3. Explicitly blocked owners: bank inventory, saved variables, instance
       scripts/data, raw flags, game-object loot state, honor rank, and creature
       formations.

    The inventory includes every schema column whose normalized name is
    `condition_id`, `conditionId`, `required_condition`, or `RequiredCondition`.
    Combinator traversal follows `NOT`, `AND`, `OR`, map-event target conditions,
    and game-object fit-condition children.

    Conditioned reference expansion is denied when no authoritative fact owner
    can evaluate it. The pinned database has five such rows, all requiring
    blocked instance data; their references are skipped rather than approximated.
    `npc_vendor_template` composition remains outside the vendor
    loader because the current creature cache does not model VMangos `vendor_id`.
    """
  end

  def type_name(type), do: Map.get(@type_names, type, {:unsupported, type})

  defp discover_consumers(repo) do
    tables = query(repo, "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")

    tables
    |> Enum.flat_map(fn [table] ->
      table
      |> table_columns(repo)
      |> Enum.filter(&(String.downcase(&1) in @condition_columns))
      |> Enum.reject(&(&1 == "condition_entry"))
      |> Enum.map(&{table, &1})
    end)
  end

  defp table_columns(table, repo) do
    repo
    |> query("PRAGMA table_info(#{quote_identifier(table)})")
    |> Enum.map(fn [_cid, name | _rest] -> name end)
  end

  defp roots_by_consumer(repo, consumers) do
    Map.new(consumers, fn {table, column} ->
      sql =
        "SELECT #{quote_identifier(column)} FROM #{quote_identifier(table)} " <>
          "WHERE #{quote_identifier(column)} > 0 ORDER BY #{quote_identifier(column)}"

      roots = repo |> query(sql) |> Enum.map(fn [entry] -> entry end)
      {"#{table}.#{column}", roots}
    end)
  end

  defp condition_rows(repo) do
    repo
    |> query(
      "SELECT condition_entry, type, value1, value2, value3, value4, flags FROM conditions ORDER BY condition_entry"
    )
    |> Enum.map(fn [entry, type, value1, value2, value3, value4, flags] ->
      %{entry: entry, type: type, values: [value1, value2, value3, value4], flags: flags}
    end)
  end

  defp walk_roots(roots, rows_by_entry) do
    roots
    |> Enum.sort()
    |> Enum.reduce({MapSet.new(), MapSet.new(), MapSet.new()}, fn entry, acc ->
      walk(entry, rows_by_entry, [], acc)
    end)
  end

  defp walk(entry, rows_by_entry, path, {reachable, missing, cycles}) do
    cond do
      entry in path ->
        cycle = path |> Enum.take_while(&(&1 != entry)) |> then(&([entry | Enum.reverse(&1)] ++ [entry]))
        {MapSet.put(reachable, entry), missing, MapSet.put(cycles, cycle)}

      MapSet.member?(reachable, entry) ->
        {reachable, missing, cycles}

      true ->
        reachable = MapSet.put(reachable, entry)
        walk_row(Map.get(rows_by_entry, entry), entry, rows_by_entry, path, {reachable, missing, cycles})
    end
  end

  defp walk_row(nil, entry, _rows_by_entry, _path, {reachable, missing, cycles}) do
    {reachable, MapSet.put(missing, entry), cycles}
  end

  defp walk_row(row, entry, rows_by_entry, path, acc) do
    Enum.reduce(child_entries(row), acc, fn child, child_acc ->
      walk(child, rows_by_entry, [entry | path], child_acc)
    end)
  end

  defp child_entries(%{type: -3, values: [value1 | _]}), do: positive([value1])
  defp child_entries(%{type: type, values: values}) when type in @combinators, do: positive(values)
  defp child_entries(%{type: type, values: [_value1, value2 | _]}) when type in [47, 50], do: positive([value2])
  defp child_entries(_row), do: []

  defp positive(values), do: Enum.filter(values, &(is_integer(&1) and &1 > 0))

  defp reachable_rows(reachable, rows_by_entry) do
    reachable
    |> Enum.sort()
    |> Enum.flat_map(fn entry -> if row = Map.get(rows_by_entry, entry), do: [row], else: [] end)
  end

  defp query(repo, sql), do: SQL.query!(repo, sql, []).rows

  defp quote_identifier(identifier) do
    if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, identifier) do
      ~s("#{identifier}")
    else
      raise ArgumentError, "unsafe SQLite identifier"
    end
  end

  defp status(type) do
    cond do
      MapSet.member?(@implemented, type) -> "evaluable"
      MapSet.member?(@partial, type) -> "partial"
      Map.has_key?(@blocked_dependencies, type) -> "blocked"
      Map.has_key?(@type_names, type) -> "pending"
      true -> "unknown upstream"
    end
  end

  defp dependency(type) do
    Map.get(@blocked_dependencies, type, Map.get(@partial_dependencies, type, "-"))
  end

  defp format_ids(ids) do
    case Enum.sort(ids) do
      [] -> "none"
      entries -> Enum.join(entries, ", ")
    end
  end

  defp format_cycles(cycles) do
    case Enum.sort(cycles) do
      [] -> "none"
      entries -> Enum.map_join(entries, "; ", &Enum.join(&1, " -> "))
    end
  end
end
