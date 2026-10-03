defmodule ThistleTea.Game.Core.AI.CreatureScript.OnyxiaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.NavigationIntent
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Creature.CreatureMovement
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @onyxia 10_184
  @whelp 11_262
  @point_motion 9

  setup do
    player = Guid.from_low_guid(:player, Unique.integer())
    %{player: player, onyxia: onyxia(player, 100)}
  end

  describe "events/1" do
    test "Onyxia wakes on the pull and calls the lair into the fight", %{onyxia: onyxia, player: player} do
      %{actions: [steps]} = Enum.find(CreatureScript.events(@onyxia), &(&1.event_type == :aggro))

      assert [%ScriptStep{command: :talk, dataint: 8_286}, %ScriptStep{command: :zone_combat_pulse}] = steps

      {_onyxia, blackboard} = EventAI.enter_combat(onyxia, Blackboard.new(), player, 1_000, context(onyxia, player))
      assert blackboard.event_ai.phase == 0
    end

    test "at 65 percent she walks to the south end of her chamber to take off", %{player: player} do
      onyxia = onyxia(player, 64)
      {onyxia, blackboard} = EventAI.tick(onyxia, Blackboard.new(), 1_000, context(onyxia, player))

      assert blackboard.event_ai.phase == 1
      refute Blackboard.combat_movement?(blackboard, onyxia)
      refute Blackboard.melee_enabled?(blackboard, onyxia)
      assert [%NavigationIntent{destination: {x, y, _z}, opts: opts}] = onyxia.internal.navigation_intents
      assert {round(x), round(y)} == {-58, -216}
      assert %Effects.MovementInform{point_id: 20} = opts[:movement_inform]
    end

    test "she lifts off where she stopped and heads for the north point", %{player: player} do
      onyxia = onyxia(player, 64)

      {onyxia, _blackboard} =
        EventAI.on_movement_inform(onyxia, in_phase(1), @point_motion, 20, context(onyxia, player))

      assert CreatureMovement.flying?(onyxia)
      assert map_size(onyxia.internal.scripts.runs) == 1
    end

    test "arriving at a point she hangs there until she sends herself on", %{player: player} do
      onyxia = onyxia(player, 50)

      {onyxia, blackboard} = EventAI.on_movement_inform(onyxia, in_phase(2), @point_motion, 3, context(onyxia, player))

      assert blackboard.event_ai.phase == 13
      assert map_size(onyxia.internal.scripts.runs) == 1
    end

    test "from a point she flies on to a neighbor or breathes across the chamber", %{player: player} do
      onyxia = onyxia(player, 50)

      for {roll, destination} <- [{1, {-58, -189}}, {36, {-64, -240}}] do
        {moved, blackboard} = move_on(onyxia, 13, 3, roll, player)
        assert blackboard.event_ai.phase == 2
        assert [%NavigationIntent{destination: {x, y, _z}, opts: opts}] = moved.internal.navigation_intents
        assert {round(x), round(y)} == destination
        assert opts[:flying?]
      end

      {breathing, blackboard} = move_on(onyxia, 13, 3, 80, player)
      assert blackboard.event_ai.phase == 2
      assert breathing.internal.navigation_intents == []
      assert map_size(breathing.internal.scripts.runs) == 1
    end

    test "a send left over from another point does nothing", %{player: player} do
      onyxia = onyxia(player, 50)
      {stayed, blackboard} = move_on(onyxia, 13, 5, 1, player)

      assert blackboard.event_ai.phase == 13
      assert stayed.internal.navigation_intents == []
    end

    test "below 40 percent she lands at the nearer end of the chamber", %{player: player} do
      onyxia = onyxia(player, 39)

      for {phase, landing} <- [{13, {-60, -215}}, {17, {-9, -213}}] do
        {landed, blackboard} = EventAI.tick(onyxia, in_phase(phase), 1_000, context(onyxia, player))
        assert blackboard.event_ai.phase == 4
        assert [%NavigationIntent{destination: {x, y, _z}, opts: opts}] = landed.internal.navigation_intents
        assert {round(x), round(y)} == landing
        assert %Effects.MovementInform{point_id: 21} = opts[:movement_inform]
      end
    end

    test "landing she comes down out of the air", %{player: player} do
      onyxia = %{onyxia(player, 39) | internal: %{onyxia(player, 39).internal | creature: flying_creature()}}

      {landed, _blackboard} =
        EventAI.on_movement_inform(onyxia, in_phase(4), @point_motion, 21, context(onyxia, player))

      refute CreatureMovement.flying?(landed)
    end

    test "on the ground she roars over whatever she is casting and roars again later" do
      %{actions: [[roar | later]], inverse_phase_mask: mask} =
        Enum.find(CreatureScript.events(@onyxia), &(&1.event_type == :script_event and &1.param1 == 3))

      assert %ScriptStep{command: :cast_spell, datalong: 18_431, datalong2: 0x01, target_self?: true} = roar
      assert [%ScriptStep{command: :start_script}] = later
      assert mask == CreatureScript.only_in_phases([5])
    end

    test "an evade puts her back on the ground in her first phase", %{player: player} do
      onyxia = %{onyxia(player, 50) | internal: %{onyxia(player, 50).internal | creature: flying_creature()}}

      {onyxia, blackboard} = EventAI.on_evade(onyxia, in_phase(13), 1_000, context(onyxia, player))

      assert blackboard.event_ai.phase == 0
      refute CreatureMovement.flying?(onyxia)
    end

    test "whelps call the whole lair into the fight" do
      assert [%{event_type: :aggro, actions: [[%ScriptStep{command: :zone_combat_pulse}]]}] =
               CreatureScript.events(@whelp)
    end
  end

  defp move_on(onyxia, phase, point, roll, player) do
    context = %{context(onyxia, player) | random: Random.fixed(0.5, roll)}
    EventAI.on_script_event(onyxia, in_phase(phase), 1, point, onyxia.object.guid, 1_000, context)
  end

  defp in_phase(phase) do
    blackboard = Blackboard.new()
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}
  end

  defp context(%Mob{object: %Object{guid: guid}}, player) do
    observations = %{
      player => %Observation{
        guid: player,
        position: {WorldRef.open(249), 0.0, -215.0, -86.0},
        metadata: %{alive?: true}
      },
      guid => %Observation{guid: guid, metadata: %{}}
    }

    Context.new(1_000, perception: Perception.new(1_000, nil, observations, %{}))
  end

  defp flying_creature, do: %Creature{ai_events: CreatureScript.events(@onyxia), inhabit_type: 1, script_flight: true}

  defp onyxia(player, health) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @onyxia, Unique.integer()), entry: @onyxia},
      unit: %Unit{health: health, max_health: 100, level: 63, auras: [], flags: 0, target: player},
      movement_block: %MovementBlock{position: {-4.8689, -217.171, -86.7104, 3.14159}},
      internal: %Internal{
        world: WorldRef.open(249),
        in_combat: true,
        threat: %{player => 100},
        creature: %Creature{ai_events: CreatureScript.events(@onyxia), inhabit_type: 1},
        spellbook: %{}
      }
    }
  end
end
