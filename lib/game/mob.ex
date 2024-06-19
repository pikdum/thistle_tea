defmodule ThistleTea.Mob do
  use GenServer

  import ThistleTea.Game.UpdateObject, only: [generate_packet: 4]
  import ThistleTea.Util, only: [pack_guid: 1, within_range: 2]

  require Logger

  # @update_type_movement 1
  @update_type_create_object2 3
  @object_type_unit 3

  # @update_flag_all 0x10
  # @update_flag_has_position 0x40
  # @update_flag_high_guid 0x08
  @update_flag_living 0x20

  # @movement_flag_forward 0x00000001
  @movement_flag_fixed_z 0x00000800

  def start_link(creature, creature_template) do
    GenServer.start_link(__MODULE__, [creature, creature_template])
  end

  def future_position(x, y, o, speed, seconds) do
    distance = speed * seconds
    delta_x = distance * :math.cos(o)
    delta_y = distance * :math.sin(o)

    x_new = x + delta_x
    y_new = y + delta_y
    {x_new, y_new}
  end

  def random_movement(state) do
    o2 = :rand.uniform(2 * 31415) / 10000.0

    %{
      state
      | creature: %{
          state.creature
          | orientation: o2
        }
    }
  end

  @impl GenServer
  def init([creature, creature_template]) do
    Registry.register(
      ThistleTea.MobRegistry,
      creature.map,
      {creature.guid, creature.position_x, creature.position_y, creature.position_z}
    )

    update_rate = :rand.uniform(4_000) + 1_000

    Process.send_after(self(), :random_movement, update_rate)

    {:ok,
     %{
       creature: creature,
       creature_template: creature_template,
       packed_guid: pack_guid(creature.guid),
       # extract out some initial values?
       max_health: creature.curhealth,
       max_mana: creature.curmana,
       update_rate: update_rate
     }}
  end

  @impl GenServer
  def handle_info(:random_movement, state) do
    new_state = random_movement(state)
    packet = spawn_packet(new_state, @movement_flag_fixed_z)

    %{position_x: x1, position_y: y1, position_z: z1} = new_state.creature

    Registry.dispatch(ThistleTea.PlayerRegistry, new_state.creature.map, fn entries ->
      for {pid, values} <- entries do
        {_guid, x2, y2, z2} = values
        in_range = within_range({x1, y1, z1}, {x2, y2, z2})

        if in_range do
          send(pid, {:send_update_packet, packet})
        end
      end
    end)

    Process.send_after(self(), :random_movement, state.update_rate)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:spawn_packet, _from, state) do
    packet = spawn_packet(state)
    {:reply, packet, state}
  end

  def spawn_packet(state, movement_flags \\ 0) do
    fields = %{
      # TODO: how to avoid collision with player guids?
      object_guid: state.creature.guid,
      object_type: 9,
      object_scale_x: 1.0,
      unit_health: state.creature.curhealth,
      unit_power_1: state.creature.curmana,
      unit_max_health: state.max_health,
      unit_max_power_1: state.max_mana,
      unit_level: 1,
      unit_faction_template: state.creature_template.faction_alliance,
      unit_flags: state.creature_template.unit_flags,
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
      walk_speed: state.creature_template.speed_walk,
      run_speed: state.creature_template.speed_run,
      run_back_speed: state.creature_template.speed_run,
      swim_speed: state.creature_template.speed_run,
      swim_back_speed: state.creature_template.speed_run,
      turn_rate: 3.1415
    }

    generate_packet(@update_type_create_object2, @object_type_unit, fields, mb)
  end
end
