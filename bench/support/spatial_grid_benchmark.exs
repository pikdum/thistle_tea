defmodule ThistleTea.Bench.SpatialGridBenchmark do
  @moduledoc false

  import Ecto.Query

  alias ThistleTea.DB.Mangos.Creature
  alias ThistleTea.DB.Mangos.Repo

  @default_cell_sizes [32, 48, 64, 96, 125, 160, 250]
  @default_query_radii [2, 10, 30, 60, 100, 250]
  @client_projection_ms 750
  @fast_run_speed 70.0

  defmodule Index do
    @moduledoc false

    @enforce_keys [:cell_size, :cells, :entities, :projections]
    defstruct [:cell_size, :cells, :entities, :projections]
  end

  def run do
    config = config()
    validate_config!(config)
    {repo, repo_started?} = start_repo!()

    try do
      entities = load_entities(config)
      projections = projections(entities, config)
      queries = query_inputs(entities, config)
      moves = relocation_inputs(entities, config)
      query_indices = build_indices(config.cell_sizes, entities, projections)
      relocation_indices = build_indices(config.cell_sizes, entities, projections)

      try do
        print_workload(config, entities, projections, queries, moves)
        validate_queries!(query_indices, queries)
        print_grid_metrics(query_indices, queries, moves)
        run_query_benchmarks(query_indices, queries, config)
        run_relocation_benchmarks(relocation_indices, moves, config)
      after
        destroy_indices(query_indices ++ relocation_indices)
      end
    after
      if repo_started?, do: GenServer.stop(repo)
    end
  end

  defp config do
    %{
      cell_sizes: integer_list("SPATIAL_BENCH_CELL_SIZES", @default_cell_sizes),
      query_radii: integer_list("SPATIAL_BENCH_QUERY_RADII", @default_query_radii),
      maps: integer_list("SPATIAL_BENCH_MAPS", [0, 1]),
      entity_limit: optional_positive_integer("SPATIAL_BENCH_ENTITY_LIMIT"),
      query_count: positive_integer("SPATIAL_BENCH_QUERY_COUNT", 256),
      relocation_count: positive_integer("SPATIAL_BENCH_RELOCATION_COUNT", 1_024),
      projected_percent: percentage("SPATIAL_BENCH_PROJECTED_PERCENT", 30),
      projection_drift: positive_number("SPATIAL_BENCH_PROJECTION_DRIFT", 10.0),
      relocation_distance: positive_number("SPATIAL_BENCH_RELOCATION_DISTANCE", 7.0),
      time: positive_number("SPATIAL_BENCH_TIME", 1.0),
      warmup: non_negative_number("SPATIAL_BENCH_WARMUP", 0.5)
    }
  end

  defp validate_config!(config) do
    validate_unique!("SPATIAL_BENCH_CELL_SIZES", config.cell_sizes)
    validate_unique!("SPATIAL_BENCH_QUERY_RADII", config.query_radii)
    minimum_margin = config.cell_sizes |> Enum.min() |> max_cell_drift()

    if config.projection_drift > minimum_margin do
      raise "SPATIAL_BENCH_PROJECTION_DRIFT must not exceed the smallest grid's projection margin #{minimum_margin}"
    end
  end

  defp start_repo! do
    {:ok, _applications} = Application.ensure_all_started(:ecto_sqlite3)

    case Repo.start_link(pool_size: 1) do
      {:ok, pid} -> {pid, true}
      {:error, {:already_started, pid}} -> {pid, false}
      {:error, reason} -> raise "could not start VMangos repo: #{inspect(reason)}"
    end
  end

  defp load_entities(config) do
    query =
      from(c in Creature,
        where: c.map in ^config.maps,
        order_by: c.guid,
        select: {c.guid, c.map, c.position_x, c.position_y, c.position_z}
      )

    entities = Repo.all(query)
    entities = if config.entity_limit, do: Enum.take(entities, config.entity_limit), else: entities

    if entities == [] do
      raise "no creature spawns found for maps #{inspect(config.maps)}"
    end

    entities
  end

  defp projections(entities, config) do
    threshold = config.projected_percent

    entities
    |> Enum.flat_map(fn {guid, world, x, y, z} ->
      if rem(guid, 100) < threshold do
        angle = rem(guid * 137, 360) * :math.pi() / 180
        dx = :math.cos(angle) * config.projection_drift
        dy = :math.sin(angle) * config.projection_drift
        [{guid, world, x + dx, y + dy, z}]
      else
        []
      end
    end)
  end

  defp query_inputs(entities, config) do
    anchors = evenly_sample(entities, config.query_count)

    Enum.map(config.query_radii, fn radius ->
      queries = Enum.map(anchors, fn {_guid, world, x, y, z} -> {world, x, y, z, radius} end)
      {"radius=#{radius}yd", queries}
    end)
  end

  defp relocation_inputs(entities, config) do
    entities
    |> evenly_sample(config.relocation_count)
    |> Enum.map(fn {guid, world, x, y, z} ->
      angle = rem(guid * 193, 360) * :math.pi() / 180
      dx = :math.cos(angle) * config.relocation_distance
      dy = :math.sin(angle) * config.relocation_distance
      {guid, {world, x, y, z}, {world, x + dx, y + dy, z}}
    end)
  end

  defp evenly_sample(values, count) do
    stride = max(div(length(values), count), 1)

    values
    |> Enum.take_every(stride)
    |> Enum.take(count)
  end

  defp build_indices(cell_sizes, entities, projections) do
    Enum.map(cell_sizes, &build_index(&1, entities, projections))
  end

  defp build_index(cell_size, entities, projections) do
    cells = :ets.new(:spatial_bench_cells, [:public, :duplicate_bag, read_concurrency: true, write_concurrency: :auto])
    entity_table = :ets.new(:spatial_bench_entities, [:public, :set, read_concurrency: true, write_concurrency: :auto])
    projection_table = :ets.new(:spatial_bench_projections, [:public, :set, read_concurrency: true])

    cell_rows = Enum.map(entities, fn {guid, world, x, y, _z} -> {cell(world, x, y, cell_size), guid} end)
    :ets.insert(cells, cell_rows)
    :ets.insert(entity_table, entities)
    :ets.insert(projection_table, Enum.map(projections, fn {guid, world, x, y, z} -> {guid, world, x, y, z} end))

    %Index{cell_size: cell_size, cells: cells, entities: entity_table, projections: projection_table}
  end

  defp destroy_indices(indices) do
    Enum.each(indices, fn index ->
      :ets.delete(index.cells)
      :ets.delete(index.entities)
      :ets.delete(index.projections)
    end)
  end

  defp run_query_benchmarks(indices, inputs, config) do
    jobs =
      Map.new(indices, fn index ->
        {job_name(index), fn queries -> query_batch(index, queries) end}
      end)

    IO.puts("\nExact projected-position query batches")

    Benchee.run(jobs,
      inputs: inputs,
      time: config.time,
      warmup: config.warmup,
      memory_time: 0,
      reduction_time: 0,
      parallel: 1
    )
  end

  defp run_relocation_benchmarks(indices, moves, config) do
    jobs =
      Map.new(indices, fn index ->
        {job_name(index), fn -> relocate_batch(index, moves) end}
      end)

    IO.puts("\nSpatial publication batches")

    Benchee.run(jobs,
      time: config.time,
      warmup: config.warmup,
      memory_time: 0,
      reduction_time: 0,
      parallel: 1
    )
  end

  defp query_batch(index, queries) do
    Enum.reduce(queries, 0, fn query, hits -> hits + exact_count(index, query) end)
  end

  defp exact_count(%Index{} = index, {world, x, y, z, range}) do
    broad_range = range + max_cell_drift(index.cell_size)
    max_distance_squared = range * range

    index
    |> candidates(world, x, y, broad_range)
    |> Enum.count(fn guid ->
      case resolved_position(index, guid) do
        {^world, tx, ty, tz} -> squared_distance({x, y, z}, {tx, ty, tz}) <= max_distance_squared
        _missing -> false
      end
    end)
  end

  defp candidates(%Index{} = index, world, x, y, range) do
    {^world, cx, cy} = cell(world, x, y, index.cell_size)
    cell_range = div(round(range), index.cell_size) + 1

    for dx <- -cell_range..cell_range,
        dy <- -cell_range..cell_range,
        {{^world, _cell_x, _cell_y}, guid} <- :ets.lookup(index.cells, {world, cx + dx, cy + dy}) do
      guid
    end
  end

  defp resolved_position(%Index{} = index, guid) do
    case :ets.lookup(index.projections, guid) do
      [{^guid, world, x, y, z}] ->
        {world, x, y, z}

      [] ->
        case :ets.lookup(index.entities, guid) do
          [{^guid, world, x, y, z}] -> {world, x, y, z}
          [] -> nil
        end
    end
  end

  defp relocate_batch(index, moves) do
    Enum.reduce(moves, 0, fn {guid, first, second}, crossings ->
      current = entity_position(index, guid)
      destination = if current == first, do: second, else: first
      update(index, guid, current, destination)

      if cell_changed?(current, destination, index.cell_size), do: crossings + 1, else: crossings
    end)
  end

  defp entity_position(%Index{} = index, guid) do
    [{^guid, world, x, y, z}] = :ets.lookup(index.entities, guid)
    {world, x, y, z}
  end

  defp update(%Index{} = index, guid, {old_world, old_x, old_y, _old_z}, {world, x, y, z}) do
    old_cell = cell(old_world, old_x, old_y, index.cell_size)
    new_cell = cell(world, x, y, index.cell_size)
    :ets.insert(index.entities, {guid, world, x, y, z})

    if old_cell != new_cell do
      :ets.delete_object(index.cells, {old_cell, guid})
      :ets.insert(index.cells, {new_cell, guid})
    end
  end

  defp validate_queries!(indices, inputs) do
    Enum.each(inputs, fn {name, queries} ->
      results = Enum.map(indices, &query_batch(&1, queries))

      if Enum.uniq(results) |> length() != 1 do
        raise "grid sizes returned different exact results for #{name}: #{inspect(results)}"
      end
    end)
  end

  defp print_workload(config, entities, projections, queries, moves) do
    IO.puts("Spatial grid workload")
    IO.puts("  maps: #{Enum.join(config.maps, ", ")}")
    IO.puts("  creature spawns: #{length(entities)}")

    IO.puts(
      "  projected positions: #{length(projections)} (#{format_number(length(projections) / length(entities) * 100)}%)"
    )

    IO.puts("  queries per invocation: #{queries |> hd() |> elem(1) |> length()}")
    IO.puts("  relocations per invocation: #{length(moves)} at #{config.relocation_distance} yards")
    IO.puts("  Benchee: #{config.warmup}s warmup + #{config.time}s measurement per scenario")
  end

  defp print_grid_metrics(indices, inputs, moves) do
    IO.puts("\nGrid metrics")
    IO.puts("  cell | margin | fast projection | avg candidates by query radius | relocation crossings")

    Enum.each(indices, fn index ->
      candidate_counts =
        Enum.map(inputs, fn {name, queries} ->
          average = average_candidates(index, queries)
          "#{String.replace_prefix(name, "radius=", "")}:#{format_number(average)}"
        end)
        |> Enum.join(" ")

      crossings = Enum.count(moves, fn {_guid, first, second} -> cell_changed?(first, second, index.cell_size) end)
      crossing_percent = crossings / length(moves) * 100
      projection_ms = min(@client_projection_ms, trunc(max_cell_drift(index.cell_size) / @fast_run_speed * 1_000))

      IO.puts(
        "  #{index.cell_size} | #{format_number(max_cell_drift(index.cell_size))}yd | #{projection_ms}ms | #{candidate_counts} | #{format_number(crossing_percent)}%"
      )
    end)
  end

  defp average_candidates(index, queries) do
    total =
      Enum.reduce(queries, 0, fn {world, x, y, _z, range}, count ->
        count + length(candidates(index, world, x, y, range + max_cell_drift(index.cell_size)))
      end)

    total / length(queries)
  end

  defp cell_changed?({world, x1, y1, _z1}, {world, x2, y2, _z2}, cell_size) do
    cell(world, x1, y1, cell_size) != cell(world, x2, y2, cell_size)
  end

  defp cell_changed?(_first, _second, _cell_size), do: true

  defp cell(world, x, y, cell_size) do
    {world, Integer.floor_div(round(x), cell_size), Integer.floor_div(round(y), cell_size)}
  end

  defp max_cell_drift(cell_size), do: :math.sqrt(2) * cell_size

  defp squared_distance({x1, y1, z1}, {x2, y2, z2}) do
    dx = x2 - x1
    dy = y2 - y1
    dz = z2 - z1
    dx * dx + dy * dy + dz * dz
  end

  defp job_name(%Index{cell_size: cell_size}), do: "cell=#{cell_size}yd"
  defp format_number(number), do: :erlang.float_to_binary(number / 1, decimals: 1)

  defp integer_list(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> value |> String.split(",", trim: true) |> Enum.map(&parse_positive_integer!(name, &1))
    end
  end

  defp validate_unique!(name, values) do
    if Enum.uniq(values) != values, do: raise("#{name} must not contain duplicates")
  end

  defp optional_positive_integer(name) do
    case System.get_env(name) do
      nil -> nil
      value -> parse_positive_integer!(name, value)
    end
  end

  defp positive_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> parse_positive_integer!(name, value)
    end
  end

  defp parse_positive_integer!(name, value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _invalid -> raise "#{name} must contain positive integers"
    end
  end

  defp percentage(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {number, ""} when number in 0..100 -> number
          _invalid -> raise "#{name} must be an integer from 0 through 100"
        end
    end
  end

  defp positive_number(name, default) do
    number = number(name, default)
    if number > 0, do: number, else: raise("#{name} must be positive")
  end

  defp non_negative_number(name, default) do
    number = number(name, default)
    if number >= 0, do: number, else: raise("#{name} must not be negative")
  end

  defp number(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Float.parse(value) do
          {number, ""} -> number
          _invalid -> raise "#{name} must be a number"
        end
    end
  end
end
