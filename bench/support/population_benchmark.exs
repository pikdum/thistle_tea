defmodule ThistleTea.Bench.PopulationBenchmark.Transport do
  @moduledoc false
  def send(_socket, _bytes), do: :ok
end

defmodule ThistleTea.Bench.PopulationBenchmark.Connection do
  @moduledoc false
  use GenServer

  alias ThistleTea.Bench.PopulationBenchmark.Transport
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Send

  def start_link do
    GenServer.start_link(__MODULE__, nil)
  end

  def init(_) do
    span = ThousandIsland.Telemetry.start_span(:connection, %{}, %{handler: __MODULE__})

    socket = %ThousandIsland.Socket{
      socket: nil,
      transport_module: Transport,
      read_timeout: :infinity,
      silent_terminate_on_error: true,
      span: span
    }

    {:ok, {socket, %{conn: %Connection{session_key: :binary.copy(<<7>>, 40)}}}}
  end

  def handle_cast({:write_packet, packet}, {socket, state}),
    do: {:noreply, {socket, Send.send_packet(packet, {socket, state})}}

  def handle_call(:drain, _from, state), do: {:reply, :ok, state}
end

defmodule ThistleTea.Bench.PopulationBenchmark do
  @moduledoc "Synthetic populations running the production owner loops and packet encoders."
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_HEARTBEAT, :CMSG_ATTACKSWING, :CMSG_CAST_SPELL]

  alias ThistleTea.Auth.Account
  alias ThistleTea.Bench.PopulationBenchmark.Connection
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound.CmsgAttackswing
  alias ThistleTea.Game.Inbound.CmsgCastSpell
  alias ThistleTea.Game.Inbound.CmsgSetActiveMover
  alias ThistleTea.Game.Network.Message.MsgMove
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.World.Entity.Player.Stats
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Telemetry
  alias ThistleTea.Telemetry.Runtime

  def run do
    config = %{
      players: integer("PLAYERS", 12),
      mobs: integer("MOBS", 80),
      copies: integer("COPIES", 2),
      duration_ms: integer("DURATION_MS", 5_000),
      interval_ms: integer("INTERVAL_MS", 100),
      warmup_ms: integer("WARMUP_MS", 1_000),
      pet_percent: integer("PET_PERCENT", 25)
    }

    scenarios = System.get_env("POPULATION_BENCH_SCENARIOS", "idle,movement,combat,stealth") |> String.split(",")

    Enum.each([:players, :mobs, :copies, :duration_ms, :interval_ms], fn field ->
      if Map.fetch!(config, field) <= 0, do: raise("#{field} must be positive")
    end)

    if !(config.pet_percent in 0..100 and config.warmup_ms >= 0), do: raise("invalid pet percentage or warmup")
    results = Enum.map(scenarios, &scenario(&1, config))

    report = %{
      config: config,
      environment: %{
        elixir: System.version(),
        otp: List.to_string(:erlang.system_info(:otp_release)),
        schedulers: :erlang.system_info(:schedulers_online),
        commit: git_commit()
      },
      results: results
    }

    output = System.get_env("POPULATION_BENCH_OUTPUT", "/tmp/thistle-population.json")
    File.write!(output, Jason.encode!(report, pretty: true))
    IO.puts("Population report: #{output}")
  end

  defp scenario(name, config) when name in ["idle", "movement", "combat", "stealth"] do
    population = prepare(name, config)

    try do
      drive(population, name, config, config.warmup_ms)
      initial_owners = Runtime.owners(population.pids)
      initial_timers = timers(population)
      before = Telemetry.checkpoint()
      profiling? = System.get_env("POPULATION_BENCH_PROFILE") == name
      if profiling?, do: start_profile(population.pids)
      samples = drive(population, name, config, config.duration_ms)
      if profiling?, do: stop_profile()

      Enum.each(population.players, fn %{pid: pid, connection: connection} ->
        :sys.get_state(pid)
        GenServer.call(connection, :drain)
      end)

      current = Telemetry.checkpoint()
      final_owners = Runtime.owners(population.pids)
      queues = Enum.map(samples, & &1.queue_max)

      result = %{
        scenario: name,
        profiled: profiling?,
        target_input_rate: if(name == "idle", do: 0, else: config.players * 1_000 / config.interval_ms),
        metrics: Telemetry.report(before, current),
        owners_before: initial_owners,
        owners_after: final_owners,
        queue_peak: Enum.max(queues, fn -> 0 end),
        timer_counts_before: initial_timers,
        timer_counts_after: timers(population),
        isolation: isolation(population)
      }

      IO.puts("#{name}: #{inspect(result, limit: :infinity)}")
      if !result.isolation, do: raise("population leaked visibility across world copies")
      if final_owners.count != length(population.pids), do: raise("a population owner stopped during measurement")
      result
    after
      cleanup(population)
    end
  end

  defp prepare(name, config) do
    players = for index <- 1..config.players, do: player(index, config)
    mobs = for index <- 1..config.mobs, do: mob(index, name, config)

    pets =
      players
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {owner, index} ->
        if rem(index * 37, 100) < config.pet_percent, do: [pet(owner)], else: []
      end)

    if name == "stealth" do
      Enum.each(
        players,
        &input(&1, %CmsgCastSpell{spell_id: 1784, spell_cast_targets: <<0::little-size(16)>>}, @cmsg_cast_spell)
      )
    end

    if name == "combat" do
      Enum.each(players, fn owner ->
        target = Enum.find(mobs, &(&1.world == owner.world))
        input(owner, %CmsgAttackswing{target_guid: target.guid}, @cmsg_attackswing)
      end)
    end

    %{
      players: players,
      mobs: mobs,
      pets: pets,
      pids: Enum.map(players ++ mobs ++ pets, & &1.pid) ++ Enum.map(players, & &1.connection)
    }
  end

  defp player(index, config) do
    account = %Account{id: 100_000 + index, username: "BENCH#{index}"}

    params = %{
      name: "Bench#{System.unique_integer([:positive])}",
      race: 1,
      class: 4,
      gender: 0,
      skin_color: 0,
      face: 0,
      hair_style: 0,
      hair_color: 0,
      facial_hair: 0,
      outfit_id: 0
    }

    character = CharacterLoader.build(params, account.id)
    character = Stats.apply(character, Stats.get!(1, 4, 60))

    character = %{
      character
      | internal: %{
          character.internal
          | spells: [1784 | character.internal.spells],
            godmode: true,
            world: WorldRef.open(451)
        },
        movement_block: %{character.movement_block | position: pose(index)}
    }

    {:ok, character} = Characters.create(character)
    {:ok, connection} = Connection.start_link()
    {:ok, pid} = PlayerServer.start_link({account, connection, character.id})
    :ok = PlayerServer.handle_message(pid, %CmsgSetActiveMover{guid: character.id})
    world = world(index, config)

    :sys.replace_state(pid, fn state ->
      state = Visibility.leave_player(state)
      character = %{state.character | internal: %{state.character.internal | world: world}}
      Presence.relocate(character)
      %{state | character: character} |> Visibility.enter_player() |> PlayerServer.maybe_broadcast_update()
    end)

    %{pid: pid, connection: connection, guid: character.id, world: world, index: index}
  end

  defp mob(index, name, config) do
    world = world(index, config)
    mob = Summon.build(38, world, pose(index), level: 50)
    unit = %{mob.unit | faction_template: if(name == "combat", do: 17, else: 35)}
    mob = %{mob | unit: unit, internal: %{mob.internal | godmode: true}}
    {:ok, pid} = MobLoader.start_mob(mob)
    %{pid: pid, guid: mob.object.guid, world: world}
  end

  defp pet(owner) do
    character = :sys.get_state(owner.pid).character
    pet = Summon.build_pet(416, character)
    {:ok, pid} = MobLoader.start_mob(pet)
    send(owner.pid, Attachment.from_pet(pet, pid, 688))
    :sys.get_state(owner.pid)
    %{pid: pid, guid: pet.object.guid, world: owner.world}
  end

  defp drive(population, name, config, duration) do
    deadline = System.monotonic_time(:millisecond) + duration
    drive_until(population, name, config, deadline, 0, [])
  end

  defp drive_until(population, name, config, deadline, step, samples) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      Enum.reverse(samples)
    else
      if name != "idle" do
        population.players
        |> Task.async_stream(fn owner -> move(owner, step) end, ordered: false, timeout: 30_000)
        |> Enum.each(fn {:ok, :ok} -> :ok end)
      end

      sample = Runtime.owners(population.pids)
      elapsed = System.monotonic_time(:millisecond) - now
      Process.sleep(max(config.interval_ms - elapsed, 0))
      drive_until(population, name, config, deadline, step + 1, [sample | samples])
    end
  end

  defp move(owner, step) do
    {x, y, z, orientation} = pose(owner.index)

    movement = %MovementBlock{
      movement_flags: 0,
      timestamp: Time.now(),
      fall_time: 0,
      position: {x + 3 * :math.sin(step / 5), y + 3 * :math.cos(step / 5), z, orientation}
    }

    packet = %MsgMove{opcode: @msg_move_heartbeat, payload: MovementBlock.movement_info_to_binary(movement)}
    input(owner, packet, @msg_move_heartbeat)
  end

  defp input(owner, message, opcode) do
    :telemetry.span([:thistle_tea, :handle_packet], %{opcode: opcode}, fn ->
      {PlayerServer.handle_message(owner.pid, message), %{opcode: opcode}}
    end)
  end

  defp timers(population) do
    players = Enum.map(population.players, &:sys.get_state(&1.pid))
    mobs = Enum.map(population.mobs ++ population.pets, &:sys.get_state(&1.pid))
    internals = Enum.map(players, & &1.character.internal) ++ Enum.map(mobs, & &1.internal)

    %{
      player_ticks: Enum.count(players, &is_reference(&1.player_tick_ref)),
      mob_ticks: Enum.count(mobs, &is_reference(&1.internal.ai_tick_ref)),
      proximity_contacts: Enum.sum(Enum.map(internals, &map_size(&1.proximity_checks))),
      proximity_refreshes: Enum.count(internals, &(not is_nil(&1.proximity_refresh))),
      quest_refreshes: Enum.count(players, &is_reference(&1.quest_refresh))
    }
  end

  defp isolation(population) do
    Enum.all?(population.players, fn owner ->
      state = :sys.get_state(owner.pid)

      foreign =
        for entity <- population.players ++ population.mobs ++ population.pets,
            entity.world != owner.world,
            do: entity.guid

      state.ready and MapSet.size(state.tracked_entities) > 0 and
        Enum.all?(foreign, &(not MapSet.member?(state.tracked_entities, &1)))
    end)
  end

  defp cleanup(population) do
    Enum.each(population.players, &PlayerServer.disconnect(&1.pid))

    Enum.each(population.mobs ++ population.pets, fn entity ->
      if Process.alive?(entity.pid), do: GenServer.stop(entity.pid)
    end)

    Enum.each(population.players, fn owner ->
      GenServer.stop(owner.connection)
      :ets.delete(CharacterStore, owner.guid)
    end)
  end

  defp pose(index), do: {16_303.2 + rem(index, 10) * 3, 16_318.1 + div(index, 10) * 3, 69.44, 0.0}
  defp world(index, config), do: %WorldRef{map_id: 451, instance_id: 8_000_000 + rem(index - 1, config.copies)}

  defp integer(name, default),
    do: System.get_env("POPULATION_BENCH_#{name}", Integer.to_string(default)) |> String.to_integer()

  defp git_commit, do: System.cmd("git", ["rev-parse", "HEAD"]) |> elem(0) |> String.trim()

  defp start_profile(pids) do
    if path = System.get_env("POPULATION_BENCH_ERLANG_TOOLS"), do: :code.add_patha(String.to_charlist(path))

    if !Code.ensure_loaded?(:eprof),
      do: raise("eprof unavailable; set POPULATION_BENCH_ERLANG_TOOLS to the matching Erlang tools ebin directory")

    apply(:eprof, :start, [])
    apply(:eprof, :start_profiling, [pids])
  end

  defp stop_profile do
    apply(:eprof, :stop_profiling, [])
    apply(:eprof, :analyze, [:total, [sort: :time]])
    apply(:eprof, :stop, [])
  end
end
