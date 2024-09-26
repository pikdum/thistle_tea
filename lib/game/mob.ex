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
  @creature_guid_offset 0xF1300000

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
    spline_id = 0
    # NO_SPLINE
    spline_flags = 0x400
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

  def take_damage(state, damage) do
    new_health = max(state.creature.curhealth - damage, 0)

    state = state |> Map.put(:creature, %{state.creature | curhealth: new_health})

    if new_health == 0 do
      with pid when not is_nil(pid) <- Map.get(state, :behavior_pid) do
        GenServer.stop(pid)
      end

      # cancel any movement if dead
      Map.get(state, :movement_timers, [])
      |> Enum.each(&Process.cancel_timer/1)

      respawn_timer = state.creature.spawntimesecs * 1_000
      Process.send_after(self(), :respawn, respawn_timer)

      state
      |> Map.put(:movement_flags, 0)
      |> Map.delete(:behavior_pid)
      |> Map.delete(:movement_timers)
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

    state =
      %{
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
        z0: creature.position_z,
        initial_point: creature.currentwaypoint
      }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:update_position, {x, y, z}}, state) do
    state =
      state |> Map.put(:creature, %{state.creature | position_x: x, position_y: y, position_z: z})

    SpatialHash.update(:mobs, state.creature.guid, self(), state.creature.map, x, y, z)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:follow_path, state) do
    state = follow_path(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:respawn, state) do
    Process.exit(self(), :normal)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:sleep_timer, state) do
    with _pid <- Map.get(state, :behavior_pid) do
      GenServer.cast(self(), :try_sleep)
      Process.send_after(self(), :sleep_timer, 60_000)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:wake_up, state) do
    case {
      Map.get(state, :behavior_pid),
      state.creature.movement_type,
      state.creature.creature_movement
    } do
      {nil, 1, _} ->
        {:ok, behavior_pid} =
          ThistleTea.WanderBehavior.start_link(%{
            pid: self(),
            guid: state.creature.guid,
            x0: state.x0,
            y0: state.y0,
            z0: state.z0,
            map: state.creature.map,
            wander_distance: state.creature.spawndist
          })

        {:noreply, state |> Map.put(:behavior_pid, behavior_pid)}

      {nil, 2, []} ->
        # no movement data, but follow path movement_type
        # probably never happens?
        {:noreply, state}

      {nil, 2, waypoints} ->
        {:ok, behavior_pid} =
          ThistleTea.FollowPathBehavior.start_link(%{
            pid: self(),
            guid: state.creature.guid,
            map: state.creature.map,
            waypoints: waypoints,
            initial_point: state.initial_point
          })

        {:noreply, state |> Map.put(:behavior_pid, behavior_pid)}

      {_, _, _} ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:try_sleep, state) do
    case Map.get(state, :behavior_pid) do
      nil ->
        {:noreply, state}

      pid ->
        %{position_x: x, position_y: y, position_z: z, map: map} = state.creature
        nearby_players = SpatialHash.query(:players, map, x, y, z, 250)

        if Enum.empty?(nearby_players) do
          GenServer.stop(pid)
          {:noreply, state |> Map.delete(:behavior_pid)}
        else
          {:noreply, state}
        end
    end
  end

  @impl GenServer
  def handle_cast({:set_initial_point, point}, state) do
    {:noreply, state |> Map.put(:initial_point, point)}
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

  @impl GenServer
  def handle_call(:get_entity, _from, state) do
    {:reply, :mob, state}
  end

  @impl GenServer
  def handle_call(:get_behavior, _from, state) do
    with behavior_pid when not is_nil(behavior_pid) <- Map.get(state, :behavior_pid),
         behavior_state <- GenServer.call(behavior_pid, :get_state) do
      {:reply, {:ok, behavior_state}, state}
    else
      _ -> {:reply, {:error, "No behavior."}, state}
    end
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
    path_timer = Process.send_after(self(), :follow_path, delay)
    state |> Map.put(:path_timer, path_timer)
  end

  def follow_path(state) do
    case Map.get(state, :path) do
      [{x1, y1, z1} | rest] ->
        %{position_x: x0, position_y: y0, position_z: z0} = state.creature
        speed = state.creature.creature_template.speed_walk

        duration =
          (calculate_movement_duration({x0, y0, z0}, {x1, y1, z1}, speed) * 1_000)
          |> trunc()
          |> max(1)

        packet = move_packet(state, {x0, y0, z0}, {x1, y1, z1}, duration)

        # calculate where mob will be in 10ms increments
        increments =
          for t <- 0..(duration - 10)//10 do
            ratio = t / duration
            x = x0 + ratio * (x1 - x0)
            y = y0 + ratio * (y1 - y0)
            z = z0 + ratio * (z1 - z0)
            {t, {x, y, z}}
          end ++ [{duration, {x1, y1, z1}}]

        # start timers to update position
        timers =
          Enum.map(increments, fn {t, {x, y, z}} ->
            Process.send_after(self(), {:update_position, {x, y, z}}, t)
          end)

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
        |> Map.put(:movement_timers, timers)
        |> send_movement_packet(packet)
        |> queue_follow_path(duration)

      _ ->
        with pid <- Map.get(state, :behavior_pid) do
          GenServer.cast(pid, :movement_finished)
        end

        state
        |> Map.delete(:path_timer)
        |> Map.delete(:movement_timers)
    end
  end

  defp get_scale(state) do
    # no idea why it's like this
    if state.creature.creature_template.scale > 0 do
      state.creature.creature_template.scale
    else
      1.0
    end
  end

  def update_packet(state, movement_flags \\ 0) do
    fields = %{
      object_guid: state.creature.guid,
      # unit + object
      object_type: 9,
      object_entry: state.creature.id,
      object_scale_x: get_scale(state),
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
