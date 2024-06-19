defmodule ThistleTea.Mob do
  use GenServer

  import ThistleTea.Game.UpdateObject, only: [generate_packet: 4]

  require Logger

  @update_type_create_object2 3
  @object_type_unit 3
  @update_flag_living 0x20

  def start_link(creature, creature_template) do
    GenServer.start_link(__MODULE__, [creature, creature_template])
  end

  @impl GenServer
  def init([creature, creature_template]) do
    Registry.register(
      ThistleTea.Mobs,
      "usezonehere",
      {creature.guid, creature.position_x, creature.position_y, creature.position_z}
    )

    {:ok,
     %{
       creature: creature,
       creature_template: creature_template,
       # extract out some initial values?
       max_health: creature.curhealth,
       max_mana: creature.curmana
     }}
  end

  @impl GenServer
  def handle_call(:spawn_packet, _from, state) do
    packet = spawn_packet(state)
    {:reply, packet, state}
  end

  def spawn_packet(state) do
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
      movement_flags: 0,
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
