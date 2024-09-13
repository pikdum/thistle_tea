defmodule ThistleTea.Mob do
  use GenServer

  import ThistleTea.Game.UpdateObject, only: [generate_packet: 4]

  import ThistleTea.Util,
    only: [
      pack_guid: 1,
      random_int: 2,
      calculate_movement_duration: 3
    ]

  require Logger

  # prevent collisions with player guids
  @creature_guid_offset 0x100000

  # @update_type_movement 1
  @update_type_create_object2 3
  @object_type_unit 3

  # @update_flag_all 0x10
  # @update_flag_has_position 0x40
  # @update_flag_high_guid 0x08
  @update_flag_living 0x20

  # @movement_flag_forward 0x00000001
  # @movement_flag_fixed_z 0x00000800

  @smsg_attackerstateupdate 0x14A

  @smsg_monster_move 0x0DD

  def start_link(creature) do
    GenServer.start_link(__MODULE__, creature)
  end

  def future_position(x, y, o, speed, seconds) do
    distance = speed * seconds
    delta_x = distance * :math.cos(o)
    delta_y = distance * :math.sin(o)

    x_new = x + delta_x
    y_new = y + delta_y
    {x_new, y_new}
  end

  def move_packet(state, {x0, y0, z0}, {x1, y1, z1}, duration) do
    packed_guid = state.packed_guid

    move_type = 0
    spline_id = random_int(1, 10_000_000)
    spline_flags = 0
    spline_count = 1

    # TODO: figure out how to do multiple spline points
    packed_guid <>
      <<
        # initial position
        x0::little-float-size(32),
        y0::little-float-size(32),
        z0::little-float-size(32),
        spline_id::little-size(32),
        move_type::little-size(8),
        spline_flags::little-size(32),
        duration::little-size(32),
        spline_count::little-size(32),
        # target position
        x1::little-float-size(32),
        y1::little-float-size(32),
        z1::little-float-size(32)
      >>
  end

  def random_movement(state) do
    with [] <- Map.get(state, :path, []),
         nil <- Map.get(state, :path_timer) do
      %{map: map} = state.creature
      %{x0: x0, y0: y0, z0: z0} = state

      {x1, y1, z1} =
        ThistleTea.Pathfinding.find_random_point_around_circle(map, {x0, y0, z0}, 10.0)

      state |> move_to({x1, y1, z1})
    else
      _ -> state
    end
  end

  def take_damage(state, damage) do
    new_health = max(state.creature.curhealth - damage, 0)

    state = state |> Map.put(:creature, %{state.creature | curhealth: new_health})

    if new_health == 0 do
      respawn_timer = state.creature.spawntimesecs * 1_000
      Process.send_after(self(), :respawn, respawn_timer)
      state |> Map.put(:movement_flags, 0)
    else
      state
    end
  end

  def face_player(state, player_guid) do
    %{position_x: x1, position_y: y1, map: map} = state.creature

    case :ets.lookup(:entities, player_guid) do
      [{^player_guid, _pid, ^map, x2, y2, _z2}] ->
        orientation = :math.atan2(y2 - y1, x2 - x1)
        state |> Map.put(:creature, %{state.creature | orientation: orientation})

      [] ->
        state
    end
  end

  def send_attacker_state_update(state, attack) do
    payload =
      <<Map.get(attack, :hit_info, 0x2)::little-size(32)>> <>
        pack_guid(Map.get(attack, :caster)) <>
        pack_guid(state.creature.guid) <>
        <<
          # damage
          Map.get(attack, :damage, 0)::little-size(32),
          # amount_of_damages
          Map.get(attack, :damage_count, 1)::little-size(8),
          # damage_state
          Map.get(attack, :damage_state, 0)::little-size(32),
          # unknown1
          0::little-size(32),
          # spell_id,
          Map.get(attack, :spell_id, 0)::little-size(32),
          # blocked_amount,
          Map.get(attack, :blocked_amount, 0)::little-size(32)
        >>

    %{position_x: x1, position_y: y1, position_z: z1, map: map} = state.creature
    nearby_players = SpatialHash.query(:players, map, x1, y1, z1, 250)

    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, @smsg_attackerstateupdate, payload})
    end
  end

  def send_updates(state) do
    packet = update_packet(state, state.movement_flags)

    %{position_x: x1, position_y: y1, position_z: z1, map: map} = state.creature
    nearby_players = SpatialHash.query(:players, map, x1, y1, z1, 250)

    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_update_packet, packet})
    end
  end

  defp randomize_rate(state) do
    # TODO: test different rates
    update_rate = :rand.uniform(90_000)
    state |> Map.put(:update_rate, update_rate)
  end

  @impl GenServer
  def init(creature) do
    creature = Map.put(creature, :guid, creature.guid + @creature_guid_offset)

    SpatialHash.update(
      :mobs,
      creature.guid,
      self(),
      creature.map,
      creature.position_x,
      creature.position_y,
      creature.position_z
    )

    # :idle - do nothing
    # :random_movement - move around randomly

    default_behavior =
      if creature.movement_type == 1 do
        :random_movement
      else
        :idle
      end

    state =
      %{
        default_behavior: default_behavior,
        current_behavior: :idle,
        creature: creature,
        packed_guid: pack_guid(creature.guid),
        # extract out some initial values?
        # movement_flags: @movement_flag_fixed_z,
        movement_flags: 0,
        max_health: creature.curhealth,
        max_mana: creature.curmana,
        level:
          random_int(creature.creature_template.min_level, creature.creature_template.max_level),
        x0: creature.position_x,
        y0: creature.position_y,
        z0: creature.position_z
      }
      |> randomize_rate()

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:behavior_event, state) do
    case {state.creature.curhealth, state.current_behavior} do
      {0, _} ->
        # don't do anything if dead
        {:noreply, state}

      {_, :random_movement} ->
        state = random_movement(state) |> randomize_rate()
        Process.send_after(self(), :behavior_event, state.update_rate)
        {:noreply, state}

      {_, _} ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:follow_path, state) do
    state = follow_path(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:respawn, state) do
    if state.current_behavior != :idle do
      # prevent counts from leaking, maybe?
      :telemetry.execute([:thistle_tea, :mob, :try_sleep], %{guid: state.creature.guid})
    end

    Process.exit(self(), :normal)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:wake_up, state) do
    case state.current_behavior do
      :idle ->
        :telemetry.execute([:thistle_tea, :mob, :wake_up], %{guid: state.creature.guid})
        Process.send_after(self(), :behavior_event, state.update_rate)
        {:noreply, state |> Map.put(:current_behavior, state.default_behavior)}

      _ ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:try_sleep, state) do
    case state.current_behavior do
      :idle ->
        {:noreply, state}

      _ ->
        %{position_x: x, position_y: y, position_z: z, map: map} = state.creature
        nearby_players = SpatialHash.query(:players, map, x, y, z, 250)

        if Enum.empty?(nearby_players) do
          :telemetry.execute([:thistle_tea, :mob, :try_sleep], %{guid: state.creature.guid})
          {:noreply, state |> Map.put(:current_behavior, :idle)}
        else
          {:noreply, state}
        end
    end
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = state |> move_to({x, y, z})
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, _spell_id}, state) do
    # TODO: look up and apply spell effects

    damage = random_int(100, 200)

    state =
      state
      |> take_damage(damage)
      |> face_player(caster)

    # attack = %{
    #   caster: caster,
    #   spell_id: spell_id,
    #   damage: damage,
    #   hit_info: 0x10000
    # }

    # send_attacker_state_update(state, attack)
    send_updates(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_attack, attack}, state) do
    # TODO: calculate damage, send over everything necessary?
    damage = random_int(Map.get(attack, :min_damage, 5), Map.get(attack, :max_damage, 25))

    state =
      state
      |> take_damage(damage)
      |> face_player(Map.get(attack, :caster))

    attack = Map.merge(attack, %{damage: damage})
    send_attacker_state_update(state, attack)
    send_updates(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    packet = update_packet(state, state.movement_flags)
    GenServer.cast(pid, {:send_update_packet, packet})
    {:noreply, state}
  end

  def send_movement_packet(state, payload) do
    %{position_x: x0, position_y: y0, position_z: z0, map: map} = state.creature
    nearby_players = SpatialHash.query(:players, map, x0, y0, z0, 250)

    for {_guid, pid, _distance} <- nearby_players do
      GenServer.cast(pid, {:send_packet, @smsg_monster_move, payload})
    end

    state
  end

  def move_to(state, {x, y, z}) do
    %{position_x: x0, position_y: y0, position_z: z0, map: map} = state.creature
    path = ThistleTea.Pathfinding.find_path(map, {x0, y0, z0}, {x, y, z})
    state |> Map.put(:path, path) |> follow_path()
  end

  def queue_follow_path(state, delay) do
    if Map.get(state, :path, []) |> Enum.count() > 0 do
      path_timer = Process.send_after(self(), :follow_path, delay)
      state |> Map.put(:path_timer, path_timer)
    else
      state |> Map.delete(:path_timer)
    end
  end

  def follow_path(state) do
    case Map.get(state, :path) do
      [{x1, y1, z1} | rest] ->
        %{position_x: x0, position_y: y0, position_z: z0} = state.creature
        speed = state.creature.creature_template.speed_walk

        duration =
          (calculate_movement_duration({x0, y0, z0}, {x1, y1, z1}, speed) * 1_000) |> trunc()

        packet = move_packet(state, {x0, y0, z0}, {x1, y1, z1}, duration)

        # TODO: this will be ahead of actual movement
        # could maybe start a timer to update in intervals?
        creature =
          state.creature
          |> Map.put(:position_x, x1)
          |> Map.put(:position_y, y1)
          |> Map.put(:position_z, z1)

        SpatialHash.update(
          :mobs,
          creature.guid,
          self(),
          creature.map,
          creature.position_x,
          creature.position_y,
          creature.position_z
        )

        state
        |> Map.put(:path, rest)
        |> Map.put(:creature, creature)
        |> send_movement_packet(packet)
        |> queue_follow_path(duration)

      _ ->
        state
    end
  end

  def update_packet(state, movement_flags \\ 0) do
    fields = %{
      object_guid: state.creature.guid,
      object_type: 9,
      object_entry: state.creature.id,
      object_scale_x: 1.0,
      unit_health: state.creature.curhealth,
      unit_power_1: state.creature.curmana,
      unit_max_health: state.max_health,
      unit_max_power_1: state.max_mana,
      unit_level: state.level,
      unit_faction_template: state.creature.creature_template.faction_alliance,
      unit_flags: state.creature.creature_template.unit_flags,
      unit_display_id: state.creature.modelid,
      unit_native_display_id: state.creature.modelid
    }

    mb = %{
      update_flag: @update_flag_living,
      x: state.creature.position_x,
      y: state.creature.position_y,
      z: state.creature.position_z,
      orientation: state.creature.orientation,
      movement_flags: movement_flags,
      # TODO: figure out how to generate these
      timestamp: 0,
      fall_time: 0.0,
      # from creature_template
      walk_speed: state.creature.creature_template.speed_walk,
      run_speed: state.creature.creature_template.speed_run,
      run_back_speed: state.creature.creature_template.speed_run,
      swim_speed: state.creature.creature_template.speed_run,
      swim_back_speed: state.creature.creature_template.speed_run,
      turn_rate: 3.1415
    }

    generate_packet(@update_type_create_object2, @object_type_unit, fields, mb)
  end
end
