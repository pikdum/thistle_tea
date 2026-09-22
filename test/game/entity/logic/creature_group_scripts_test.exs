defmodule ThistleTea.Game.Entity.Logic.CreatureGroupScriptsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Condition.Requirements
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.CombatLeashes
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.World.System.ScriptedEvent
  alias ThistleTea.Game.WorldRef

  setup [:creatures]

  describe "Script.run/5" do
    test "joins and leaves through typed effects and the explicit owner", %{
      leader: leader,
      member: member,
      world: world
    } do
      step = %ScriptStep{command: :join_creature_group, datalong: 2, position: {4.0, 0.0, 0.0, 1.5}}
      {member, _} = Script.run(member, Blackboard.new(), [step], leader.object.guid, 0)

      assert [%Effects.CreatureGroupCommand{command: {:join, _, %{distance: 4.0, angle: 1.5, flags: 2}}}] =
               member.internal.events

      member = EventSink.emit_pending(member, Context.new(self()))
      assert CreatureGroups.snapshot(world, member.object.guid).leader == 1

      {member, _} = Script.run(member, Blackboard.new(), [%ScriptStep{command: :leave_creature_group}], nil, 0)
      EventSink.emit_pending(member, Context.new(self()))
      assert CreatureGroups.snapshot(world, member.object.guid) == %{leader: nil, dead?: true}
    end
  end

  describe "Engagement.enter/4" do
    test "emits group attack once per engagement", %{leader: leader} do
      %{entity: leader} = Engagement.enter(leader, 99, 1, selection: :target)
      %{entity: leader} = Engagement.enter(leader, 99, 2, selection: :target)

      assert Enum.filter(leader.internal.events, &is_struct(&1, Effects.CreatureGroupEvent)) == [
               Effects.creature_group_event({:attack, 99, CombatLeash.reference(leader)})
             ]

      %{entity: leader} = Engagement.leave(leader, :evade)
      assert List.last(leader.internal.events) == Effects.creature_group_event(:evade)
    end

    test "group assistance shares the emitted fight clock and releases it through death", %{
      leader: leader,
      member: member,
      world: world
    } do
      CreatureGroups.join(world, member.object.guid, leader.object.guid, %Member{flags: 2}, self())
      %{entity: leader} = Engagement.enter(leader, 99, 1_000, selection: :target)
      leader = EventSink.emit_pending(leader, Context.new(self()))
      source = CombatLeash.reference(leader)
      assert_receive {:creature_group, _, {:attack, 99, ^source}}
      %{entity: member} = Engagement.enter(member, 99, 2_500, leash_source: source, selection: :target)
      member = EventSink.emit_pending(member, Context.new(self()))
      assert CombatLeashes.last_extended_at(member) == 1_000
      %{entity: leader} = Engagement.enter(leader, 99, 10_000, selection: :target)
      %{entity: leader} = Engagement.die(%{leader | unit: %{leader.unit | health: 0}})
      EventSink.emit_pending(leader, Context.new(self()))
      assert CombatLeashes.last_extended_at(source) == nil
      assert CombatLeashes.last_extended_at(member) == 10_000
      %{entity: member} = Engagement.leave(member, :evade)
      EventSink.emit_pending(member, Context.new(self()))
      assert CombatLeashes.last_extended_at(member) == nil
    end
  end

  describe "ScriptedEvent.condition_results/4" do
    test "evaluates group membership and deaths with target swapping", %{leader: leader, member: member, world: world} do
      member_condition = %Condition{entry: 1, type: :creature_group_member, value1: 1}
      dead_condition = %Condition{entry: 2, type: :creature_group_dead}
      swapped = %{member_condition | entry: 3, swap_targets?: true}
      conditions = [member_condition, dead_condition, swapped]
      assert Requirements.environment_conditions(conditions) == conditions

      assert ScriptedEvent.condition_results(world, leader.object.guid, member.object.guid, conditions) == %{
               1 => :unmet,
               2 => :met,
               3 => :unmet
             }

      CreatureGroups.join(world, member.object.guid, leader.object.guid, %Member{}, self())

      assert ScriptedEvent.condition_results(world, leader.object.guid, member.object.guid, conditions) == %{
               1 => :met,
               2 => :unmet,
               3 => :met
             }

      CreatureGroups.event(member, :death, self())
      CreatureGroups.snapshot(world, member.object.guid)

      assert ScriptedEvent.condition_results(world, leader.object.guid, member.object.guid, conditions) == %{
               1 => :met,
               2 => :met,
               3 => :met
             }

      assert %{2 => {:unknown, _}} =
               ScriptedEvent.condition_results(WorldRef.instance(36, world.instance_id + 1), leader.object.guid, nil, [
                 dead_condition
               ])
    end
  end

  defp creatures(_context) do
    world = WorldRef.instance(36, System.unique_integer([:positive]))
    leader = mob(world, 1)
    member = mob(world, 2)
    Enum.each([leader, member], &CreatureGroups.register(&1, self()))

    on_exit(fn ->
      CreatureGroups.stop_world(world)
      CombatLeashes.stop_world(world)
    end)

    %{world: world, leader: leader, member: member}
  end

  defp mob(world, id) do
    guid = Guid.from_low_guid(:mob, 7, System.unique_integer([:positive]))

    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, creature: %Creature{db_guid: id}}
    }
  end
end
