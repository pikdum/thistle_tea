defmodule ThistleTea.Bench.HotPathsBenchmark do
  @moduledoc false

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Math
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Position.Spline
  alias ThistleTea.Game.World.SpatialHash

  @groups ~w(update_object movement spatial)
  @update_flag 0x08 ||| 0x20 ||| 0x40

  def run do
    config = config()

    for group <- config.groups do
      IO.puts("\n=== #{group} ===")
      run_group(group, config)
    end
  end

  defp config do
    groups =
      case System.get_env("HOT_PATHS_GROUPS") do
        nil -> @groups
        value -> value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
      end

    unknown = groups -- @groups
    if unknown != [], do: raise(ArgumentError, "unknown HOT_PATHS_GROUPS: #{Enum.join(unknown, ", ")}")

    %{
      groups: groups,
      time: env_number("HOT_PATHS_TIME", 2.0),
      warmup: env_number("HOT_PATHS_WARMUP", 0.5),
      memory_time: env_number("HOT_PATHS_MEMORY_TIME", 0.5),
      entities: env_integer("HOT_PATHS_ENTITIES", 600),
      moving_percent: env_integer("HOT_PATHS_MOVING_PERCENT", 30),
      spacing: env_number("HOT_PATHS_SPACING", 4.0)
    }
  end

  defp run_group("update_object", config) do
    mob = mob_update(Guid.from_low_guid(:mob, 68, 1))
    player_guid = Guid.from_low_guid(:player, 1)
    player = player_update(player_guid)
    observer = Guid.from_low_guid(:player, 2)

    mob_payload = payload(%{mob | update_type: :values}, observer)
    self_payload = payload(%{player | update_type: :values}, player_guid)

    IO.puts("mob values payload: #{byte_size(mob_payload)} bytes")
    IO.puts("player self values payload: #{byte_size(self_payload)} bytes")
    IO.puts("player other values payload: #{byte_size(payload(%{player | update_type: :values}, observer))} bytes")

    benchee(
      %{
        "mob values for a player" => fn -> UpdateObject.to_packet(%{mob | update_type: :values}, observer) end,
        "mob create for a player" => fn -> UpdateObject.to_packet(mob, observer) end,
        "player values for self" => fn -> UpdateObject.to_packet(%{player | update_type: :values}, player_guid) end,
        "player values for another player" => fn ->
          UpdateObject.to_packet(%{player | update_type: :values}, observer)
        end,
        "player create for self" => fn -> UpdateObject.to_packet(player, player_guid) end,
        "zlib mob values payload" => fn -> :zlib.compress(mob_payload) end,
        "zlib player self values payload" => fn -> :zlib.compress(self_payload) end
      },
      config
    )
  end

  defp run_group("movement", config) do
    origin = {-9464.6, 62.9, 55.9}
    nodes = for step <- 1..6, do: {-9464.6 + step * 4.0, 62.9 + step * 1.5, 55.9 + step * 0.1}
    points = [origin | nodes]
    duration = 3_000

    benchee(
      %{
        "Math.distance" => fn -> Math.distance(origin, List.last(nodes)) end,
        "Movement.position_at mid-spline" => fn -> Movement.position_at(origin, nodes, duration, 1_500) end,
        "Movement.position_at finished spline" => fn -> Movement.position_at(origin, nodes, duration, 9_000) end,
        "Math.movement_duration 7-point path" => fn -> Math.movement_duration(points, 7.0) end
      },
      config
    )
  end

  defp run_group("spatial", config) do
    world = WorldRef.open(0)
    SpatialHash.setup_tables()
    guids = populate(world, config)
    now = System.monotonic_time(:millisecond)
    origins = guids |> Enum.take_every(max(div(length(guids), 32), 1)) |> Enum.map(&World.position(&1, now))

    IO.puts(
      "#{length(guids)} mobs #{config.spacing} yd apart, #{config.moving_percent}% on active splines, #{length(origins)} query origins"
    )

    benchee(
      %{
        "nearby_units_exact 30yd x#{length(origins)}" => fn ->
          Enum.each(origins, fn {w, x, y, z} -> World.nearby_units_exact(:mobs, w, {x, y, z}, 30, now) end)
        end,
        "Position.get every mob" => fn -> Enum.each(guids, &World.position(&1, now)) end
      },
      config
    )
  end

  defp populate(world, config) do
    side = config.entities |> :math.sqrt() |> ceil()
    now = System.monotonic_time(:millisecond)

    for index <- 0..(config.entities - 1) do
      guid = Guid.from_low_guid(:mob, 68, 100_000 + index)
      x = -9500.0 + rem(index, side) * config.spacing
      y = 20.0 + div(index, side) * config.spacing
      SpatialHash.insert(:mobs, guid, world, x, y, 56.0)

      if rem(index * 100, 100 * 100) < config.moving_percent * 100 do
        SpatialHash.put_projection(guid, %Spline{
          world: world,
          origin: {x, y, 56.0},
          nodes: [{x + 3.0, y + 1.0, 56.0}, {x + 6.0, y + 3.0, 56.0}],
          started_at: now,
          duration_ms: 600_000,
          falling?: false
        })
      end

      guid
    end
  end

  defp mob_update(guid) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :unit,
      object: %{filled(Object) | guid: guid, entry: 68},
      unit: %{filled(Unit) | auras: []},
      movement_block: movement_block()
    }
  end

  defp player_update(guid) do
    %UpdateObject{
      update_type: :create_object2,
      object_type: :player,
      object: %{filled(Object) | guid: guid},
      unit: %{filled(Unit) | auras: []},
      player: filled(Player),
      movement_block: movement_block()
    }
  end

  defp movement_block do
    struct!(
      %MovementBlock{
        update_flag: @update_flag,
        position: {-9464.6, 62.9, 55.9, 0.0},
        movement_flags: 0,
        timestamp: 0,
        fall_time: 0,
        turn_rate: :math.pi()
      },
      MovementBlock.player_speeds()
    )
  end

  defp filled(module) do
    base = struct(module)

    typed =
      base
      |> Map.from_struct()
      |> Map.keys()
      |> Enum.flat_map(&probe_field(module, base, &1))
      |> Map.new()

    struct(base, typed)
  end

  defp probe_field(module, base, key) do
    base
    |> Map.put(key, 1)
    |> module.to_list(:self)
    |> Enum.flat_map(fn
      {^key, _value, {_offset, size, type}} -> [{key, field_value(type, size)}]
      _entry -> []
    end)
  rescue
    _error -> []
  end

  defp field_value(:guid, _size), do: 0x0000_4000_0000_1234
  defp field_value(:int, 1), do: 1_234
  defp field_value(:int, size), do: 0x0102_0304 * size
  defp field_value(:float, _size), do: 1.5
  defp field_value(:byte, size), do: :binary.copy(<<1>>, 4 * size)
  defp field_value(:two_short, _size), do: 65_537
  defp field_value(:bytes, size), do: :binary.copy(<<2>>, 4 * size)

  defp payload(update, recipient), do: UpdateObject.to_packet(update, recipient).payload

  defp benchee(jobs, config) do
    Benchee.run(jobs,
      time: config.time,
      warmup: config.warmup,
      memory_time: config.memory_time,
      reduction_time: 0,
      parallel: 1,
      print: [fast_warning: false]
    )
  end

  defp env_number(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> value |> Float.parse() |> elem(0)
    end
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil -> default
      value -> String.to_integer(value)
    end
  end
end
