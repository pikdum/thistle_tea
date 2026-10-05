defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyGroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.BT.WaypointHold
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyGround
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

  describe "on_script_event/6" do
    test "orders start a walking commander once and the six-second rally starts running", _context do
      for entry <- [13_446, 13_449] do
        mob = creature(entry)
        route = route()
        context = Context.new(0, waypoints: Waypoints.new(%{{:script, entry, 0} => route}))
        {home, board} = EventAI.on_spawned(mob, Blackboard.new(), 0)
        assert Enum.any?(home.internal.events, &match?(%Effects.BattlegroundCreatureEvent{event: 3}, &1))
        {marching, board} = EventAI.on_script_event(home, board, 1, 0, 0, context)
        assert board.event_ai.phase == 1
        refute board.navigation.run_mode
        assert marching.unit.flags == 0x1000
        assert board.navigation.scripted_waypoint_route.points == route.points
        assert EventAI.on_script_event(marching, board, 1, 0, 1, context) == {marching, board}
        steps = Enum.find(AlteracValleyGround.routes(), &(&1.entry == entry)).points[2]
        {waiting, board} = Script.execute_steps(marching, board, steps, mob.object.guid, 1_000)
        assert WaypointHold.status(waiting, board, 6_999) == {:hold, 1}
        assert {:release, [run | calls]} = WaypointHold.status(waiting, board, 7_000)
        assert run.command == :set_run
        assert run.datalong == 1
        assert length(calls) == 4
        base = if entry == 13_446, do: 13_524, else: 13_528
        assert Enum.map(calls, & &1.datalong3) == Enum.to_list(base..(base + 3))

        for call <- calls do
          assert [
                   %{command: :talk},
                   %{command: :set_run},
                   %{command: :set_phase, datalong: 2},
                   %{command: :leave_creature_group},
                   %{command: :join_creature_group, datalong: 0x87, formation_from_position?: true}
                 ] = call.sub_scripts[1]
        end
      end
    end
  end

  describe "on_spawned/4" do
    test "every infantry tier subscribes to its own commander before the rally" do
      for entry <- 13_524..13_531 do
        mob = creature(entry)
        commander = commander(entry)
        guid = Guid.from_low_guid(:mob, commander, Unique.integer())

        observation = %Observation{
          guid: guid,
          position: {mob.internal.world, 2.0, 2.0, 3.0},
          metadata: %{entry: commander, alive?: true, orientation: 0.0}
        }

        perception =
          Perception.new(0, nil, %{guid => observation}, %{mobs: [{guid, 1.0}], players: [], game_objects: []})

        condition = Enum.find(AlteracValleyGround.events(entry), & &1.condition).condition
        context = Context.new(0, perception: perception, script_conditions: %{condition => :unmet})
        {waiting, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)

        assert %Effects.CreatureGroupCommand{command: {:join, ^guid, member}} =
                 Enum.find(waiting.internal.events, &is_struct(&1, Effects.CreatureGroupCommand))

        assert member.flags == 0x80
        assert board.event_ai.phase == 0
        assert board.navigation.scripted_waypoint_route == nil
      end
    end

    test "infantry whose commander is already missing start their own route" do
      for entry <- 13_524..13_531 do
        mob = creature(entry)
        condition = Enum.find(AlteracValleyGround.events(entry), & &1.condition).condition

        context =
          Context.new(0,
            script_conditions: %{condition => :met},
            waypoints: Waypoints.new(%{{:script, entry, 0} => route()})
          )

        {_orphan, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)
        assert board.event_ai.phase == 1
        assert board.navigation.scripted_waypoint_route.points == route().points
        assert board.navigation.run_mode
      end
    end
  end

  describe "on_group_member_died/6" do
    test "pre-rally orphans start their own route and formed survivors retain inherited movement" do
      for entry <- 13_524..13_531, phase <- [0, 2] do
        mob = creature(entry)
        board = Blackboard.new()
        board = %{board | event_ai: %{board.event_ai | phase: phase}}
        guid = Guid.from_low_guid(:mob, commander(entry), Unique.integer())
        context = Context.new(0, waypoints: Waypoints.new(%{{:script, entry, 0} => route()}))
        {untouched, board} = EventAI.on_group_member_died(mob, board, guid, commander(entry), false, context)
        assert untouched == mob
        assert board.event_ai.phase == phase
        {orphan, next} = EventAI.on_group_member_died(mob, board, guid, commander(entry), true, context)
        assert next.event_ai.phase == 1
        if phase == 0, do: assert(next.navigation.scripted_waypoint_route.points == route().points)
        assert next.navigation.run_mode
        assert EventAI.on_group_member_died(orphan, next, guid, commander(entry), true, context) == {orphan, next}
      end
    end
  end

  describe "routes/0" do
    test "commanders stop at the enemy base and every tier has an independent final home" do
      routes = AlteracValleyGround.routes()

      for {entry, point} <-
            [{13_446, 48}, {13_449, 53}] ++ Enum.map(13_524..13_531, &{&1, if(&1 < 13_528, do: 49, else: 54)}) do
        assert [%{command: :set_home_position}, %{command: :movement, datalong: 0}] =
                 Enum.find(routes, &(&1.entry == entry)).points[point]
      end

      for entry <- AlteracValleyGround.summon_entries(), do: assert(entry in CreatureScript.summon_entries())
    end
  end

  defp commander(entry) when entry < 13_528, do: 13_446
  defp commander(_entry), do: 13_449
  defp route, do: %WaypointRoute{first_point: 0, points: %{0 => %Waypoint{position: {1.0, 2.0, 3.0, 0.0}}}}

  defp creature(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, flags: 0x101, npc_flags: 2},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(30, Unique.integer()),
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        spawn: %Spawn{position: {1.0, 2.0, 3.0}}
      }
    }
  end
end
