defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyCavalryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.BT.WaypointHold
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyCavalry
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
    test "launches exactly eight corpse-timed riders and the authored route once per life" do
      for {entry, rider, display, rally, last} <- teams() do
        mob = creature(entry)
        points = Map.new(0..last, &{&1, %Waypoint{position: {&1 / 1, 2.0, 3.0, 0.0}}})
        route = %WaypointRoute{first_point: 0, points: points}
        context = Context.new(0, waypoints: Waypoints.new(%{{:script, entry, 0} => route}))
        {home, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)
        assert home.unit.mount_display_id == display
        assert notification(mob, 0) in home.internal.events
        {marching, board} = EventAI.on_script_event(home, board, 1, 0, 0, context)
        assert board.event_ai.phase == 1
        assert board.navigation.run_mode
        assert marching.unit.flags == 0x1000
        assert board.navigation.scripted_waypoint_route.points == points
        summons = Enum.filter(marching.internal.events, &is_struct(&1, Effects.SummonCreature))
        assert length(summons) == 8
        assert Enum.all?(summons, &match?(%{summon: %{entry: ^rider, despawn_type: 5, despawn_delay_ms: 10_000}}, &1))
        assert summons |> Enum.map(& &1.summon.position) |> Enum.uniq() |> length() == 8
        assert EventAI.on_script_event(marching, board, 1, 0, 1, Context.new(1)) == {marching, board}

        steps = Enum.find(AlteracValleyCavalry.routes(), &(&1.entry == entry)).points[rally]
        {waiting, board} = Script.execute_steps(marching, board, steps, mob.object.guid, 1_000)
        assert WaypointHold.status(waiting, board, 6_999) == {:hold, 1}

        assert {:release, [%{command: :start_script_for_all, datalong3: ^rider} = release]} =
                 WaypointHold.status(waiting, board, 7_000)

        assert [
                 %{command: :talk},
                 %{command: :set_run},
                 %{command: :set_phase, datalong: 2},
                 %{command: :leave_creature_group},
                 %{command: :join_creature_group, datalong: 0x87}
               ] =
                 release.sub_scripts[1]
      end
    end
  end

  describe "on_spawned/4" do
    test "riders subscribe to commander deaths while waiting for the rally" do
      for {commander, rider, _display, _rally, _last} <- teams() do
        mob = creature(rider)
        guid = Guid.from_low_guid(:mob, commander, Unique.integer())

        observation = %Observation{
          guid: guid,
          position: {mob.internal.world, 2.0, 2.0, 3.0},
          metadata: %{entry: commander, alive?: true, orientation: 0.0}
        }

        perception =
          Perception.new(0, nil, %{guid => observation}, %{mobs: [{guid, 1.0}], players: [], game_objects: []})

        condition = Enum.find(AlteracValleyCavalry.events(rider), & &1.condition).condition
        context = Context.new(0, perception: perception, script_conditions: %{condition => :unmet})
        {waiting, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)

        assert %Effects.CreatureGroupCommand{command: {:join, ^guid, member}} =
                 Enum.find(waiting.internal.events, &is_struct(&1, Effects.CreatureGroupCommand))

        assert member.flags == 0x80
        assert board.event_ai.phase == 0
        assert board.navigation.scripted_waypoint_route == nil
      end
    end

    test "a rider born without a living commander starts its own route and expiry" do
      for {_commander, rider, _display, _rally, _last} <- teams() do
        mob = creature(rider)
        condition = Enum.find(AlteracValleyCavalry.events(rider), & &1.condition).condition
        assert condition.type == :nearby_creature
        assert condition.reverse?
        assert condition.swap_targets?
        assert condition.value3 == 0
        route = %WaypointRoute{first_point: 0, points: %{0 => %Waypoint{position: {1.0, 2.0, 3.0, 0.0}}}}

        context =
          Context.new(0,
            script_conditions: %{condition => :met},
            waypoints: Waypoints.new(%{{:script, rider, 0} => route})
          )

        {orphan, board} = EventAI.on_spawned(mob, Blackboard.new(), 0, context)
        assert board.event_ai.phase == 1
        assert board.navigation.scripted_waypoint_route.points == route.points
        assert Enum.any?(orphan.internal.events, &match?(%Effects.DespawnSelf{duration_ms: 600_000}, &1))
      end
    end
  end

  describe "enter_combat/4" do
    test "commanders and riders dismount in combat and remount on evade" do
      for {commander, rider, display, _rally, _last} <- teams(), entry <- [commander, rider] do
        mob = creature(entry)
        {mounted, board} = EventAI.on_spawned(mob, Blackboard.new(), 0)
        {fighting, board} = EventAI.enter_combat(mounted, board, Unique.integer(), 1)
        assert fighting.unit.mount_display_id == 0
        {home, board} = EventAI.on_evade(fighting, board, 2)
        assert home.unit.mount_display_id == display
        assert board.navigation.run_mode
      end
    end
  end

  describe "on_group_member_died/6" do
    test "only the commander's death starts a survivor's ten-minute lifetime once" do
      for {commander, rider, _display, _rally, _last} <- teams(), phase <- [0, 2] do
        mob = creature(rider)
        board = Blackboard.new()
        board = %{board | event_ai: %{board.event_ai | phase: phase}}
        guid = Guid.from_low_guid(:mob, commander, Unique.integer())
        route = %WaypointRoute{first_point: 0, points: %{0 => %Waypoint{position: {1.0, 2.0, 3.0, 0.0}}}}
        context = Context.new(0, waypoints: Waypoints.new(%{{:script, rider, 0} => route}))
        {untouched, board} = EventAI.on_group_member_died(mob, board, guid, commander, false, context)
        assert untouched == mob
        assert board.event_ai.phase == phase
        {orphan, board} = EventAI.on_group_member_died(mob, board, guid, commander, true, context)
        assert board.event_ai.phase == 1
        if phase == 0, do: assert(board.navigation.scripted_waypoint_route.points == route.points)
        assert Enum.any?(orphan.internal.events, &match?(%Effects.DespawnSelf{duration_ms: 600_000}, &1))
        assert EventAI.on_group_member_died(orphan, board, guid, commander, true, context) == {orphan, board}
      end
    end
  end

  describe "on_death/4" do
    test "the commander reports its death and a respawn returns it to launch eligibility" do
      for {entry, _rider, display, _rally, _last} <- teams() do
        mob = creature(entry)
        {dead, _board} = EventAI.on_death(%{mob | unit: %{mob.unit | health: 0}}, Blackboard.new(), Unique.integer(), 0)
        assert notification(mob, 1) in dead.internal.events
        {home, board} = EventAI.on_spawned(Mob.respawn(dead), Blackboard.new(), 1)
        assert home.unit.mount_display_id == display
        assert notification(mob, 0) in home.internal.events
        assert board.event_ai.phase == 0
      end
    end
  end

  defp teams, do: [{13_441, 13_440, 1_166, 2, 81}, {13_577, 13_576, 2_786, 5, 92}]

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
