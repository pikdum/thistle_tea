defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAirTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAir
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "on_script_event/7" do
    test "rescuing a prisoner restores her pose and starts her authored journey once" do
      for entry <- AlteracValleyAir.entries() do
        mob = creature(entry)
        route = %WaypointRoute{first_point: 0, points: %{0 => %Waypoint{position: {1.0, 2.0, 3.0, 0.0}}}}
        context = Context.new(0, waypoints: Waypoints.new(%{{:script, entry, 0} => route}))
        {moving, board} = EventAI.on_script_event(mob, Blackboard.new(), 1, 0, 0, context)
        assert moving.unit.npc_flags == 0
        assert moving.unit.dynamic_flags == 0
        assert moving.unit.stand_state == 0
        assert moving.unit.flags == 0x1000
        assert board.event_ai.phase == 1
        assert board.navigation.scripted_waypoint_route.points == route.points
        assert board.navigation.run_mode
        assert EventAI.on_script_event(moving, board, 1, 0, 0, context) == {moving, board}
      end
    end
  end

  describe "routes/0" do
    test "arrival restores quest services, retains home and reports to the matching battleground" do
      for route <- AlteracValleyAir.routes() do
        mob = creature(route.entry)
        {_point, steps} = Enum.at(route.points, 0)
        {home, board} = Script.execute_steps(mob, Blackboard.new(), steps, mob.object.guid, 0)
        assert board.event_ai.phase == 2
        assert board.navigation.movement_override == :idle
        assert home.unit.npc_flags == 2
        assert home.internal.spawn.position == {1.0, 2.0, 3.0}

        assert %Effects.BattlegroundCreatureEvent{
                 world: mob.internal.world,
                 creature_guid: mob.object.guid,
                 creature_entry: route.entry,
                 event: 1
               } in home.internal.events
      end
    end
  end

  describe "on_spawned/4" do
    test "respawning restores the prison position, home, flags and seated poses" do
      for route <- AlteracValleyAir.routes() do
        mob = creature(route.entry)
        spawn = %{mob.internal.spawn | unit: %{mob.unit | stand_state: 0}, movement_block: mob.movement_block}
        mob = %{mob | internal: %{mob.internal | spawn: spawn}}
        at_base = %{mob | movement_block: %{mob.movement_block | position: {9.0, 8.0, 7.0, 0.0}}}
        {_point, steps} = Enum.at(route.points, 0)
        {home, board} = Script.execute_steps(at_base, Blackboard.new(), steps, mob.object.guid, 0)
        assert home.internal.spawn.position == {9.0, 8.0, 7.0}
        {dead, _board} = EventAI.on_death(%{home | unit: %{home.unit | health: 0}}, board, 0, 1)
        assert notification(mob, 0) in dead.internal.events
        respawned = Mob.respawn(dead)
        respawned = %{respawned | internal: %{respawned.internal | events: []}}
        {prisoner, board} = EventAI.on_spawned(respawned, Blackboard.new(), 2, Context.new(2))
        assert prisoner.movement_block.position == {1.0, 2.0, 3.0, 0.0}
        assert prisoner.internal.spawn.position == {1.0, 2.0, 3.0}
        assert prisoner.unit.flags == 0x101
        assert prisoner.unit.npc_flags == 2
        assert prisoner.unit.health == 100
        assert prisoner.unit.stand_state == if(route.entry in [13_439, 13_437], do: 1, else: 0)
        assert board.event_ai.phase == 0
        assert notification(mob, 0) in prisoner.internal.events
      end
    end
  end

  defp notification(mob, event) do
    %Effects.BattlegroundCreatureEvent{
      world: mob.internal.world,
      creature_guid: mob.object.guid,
      creature_entry: mob.object.entry,
      event: event
    }
  end

  defp creature(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, flags: 0x101, npc_flags: 2, dynamic_flags: 0x20, stand_state: 1},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(30, Unique.integer()),
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}}
      }
    }
  end
end
