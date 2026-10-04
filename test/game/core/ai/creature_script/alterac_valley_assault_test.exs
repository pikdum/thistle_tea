defmodule ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAssaultTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.CreatureScript.AlteracValleyAssault
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "routes/0" do
    test "each summoner becomes attackable, mounts, and creates an unowned altar only at her destination" do
      for {entry, mounted_point, walking_point, altar_point, altar} <- [
            {13_236, 6, 42, 43, 178_465},
            {13_442, 3, 48, 49, 178_670}
          ] do
        route = route(entry)
        mob = creature(entry)
        {mob, blackboard} = Script.execute_steps(mob, Blackboard.new(), route.points[0], mob.object.guid, 0)
        assert blackboard.event_ai.phase == 1
        assert Bitwise.band(mob.unit.flags, 0x101) == 0
        assert Bitwise.band(mob.unit.flags, 0x1000) != 0
        {mounted, blackboard} = Script.execute_steps(mob, blackboard, route.points[mounted_point], mob.object.guid, 0)
        assert mounted.unit.mount_display_id > 0
        assert blackboard.event_ai.phase == 2

        {walking, blackboard} =
          Script.execute_steps(mounted, blackboard, route.points[walking_point], mob.object.guid, 0)

        assert walking.unit.mount_display_id == 0
        {waiting, blackboard} = Script.execute_steps(walking, blackboard, route.points[altar_point], mob.object.guid, 0)
        assert blackboard.event_ai.phase == 3
        assert blackboard.navigation.movement_override == :idle

        assert [%Effects.SummonGameObject{entry: ^altar, owned?: false}] =
                 Enum.filter(waiting.internal.events, &is_struct(&1, Effects.SummonGameObject))
      end
    end

    test "bosses stop on their forward objectives and retain the new combat home" do
      for {entry, point} <- [{13_256, 31}, {13_419, 21}] do
        mob = creature(entry)
        {mob, blackboard} = Script.execute_steps(mob, Blackboard.new(), route(entry).points[point], mob.object.guid, 0)
        assert blackboard.navigation.movement_override == :idle
        assert mob.internal.spawn.position == {1.0, 2.0, 3.0}
      end
    end
  end

  describe "on_script_event/7" do
    test "only a summoner waiting at the altar can accept her ritual, once" do
      for {entry, event} <- [{13_236, 7_060}, {13_442, 7_268}] do
        mob = creature(entry)

        for phase <- [0, 1, 2, 4] do
          blackboard = phase(phase)
          {unchanged, unchanged_board} = EventAI.on_script_event(mob, blackboard, event, 0, 0, Context.new(0))
          assert unchanged.internal.events == []
          assert unchanged_board.event_ai.phase == phase
        end

        {accepted, blackboard} = EventAI.on_script_event(mob, phase(3), event, 0, 0, Context.new(0))
        assert blackboard.event_ai.phase == 4
        refute Enum.any?(accepted.internal.events, &is_struct(&1, Effects.SummonCreature))
        {again, board} = EventAI.on_script_event(accepted, blackboard, event, 0, 0, Context.new(0))
        assert again == accepted
        assert board == blackboard

        dead = %{mob | unit: %{mob.unit | health: 0}}
        {rejected, rejected_board} = EventAI.on_script_event(dead, phase(3), event, 0, 0, Context.new(0))
        assert rejected.internal.events == []
        assert rejected_board.event_ai.phase == 3
      end
    end
  end

  describe "events/1" do
    test "Lokholar feeds on player kills while both bosses use their combat kits" do
      assert [%{param3: 1, actions: [[_, %ScriptStep{command: :cast_spell, datalong: 21_307, target_self?: true}]]}] =
               Enum.filter(CreatureScript.events(13_256), &(&1.event_type == :kill))

      for {entry, spells} <- [
            {13_256, [21_367, 21_369, 14_907, 19_133, 15_878, 16_869]},
            {13_419, [20_654, 21_670, 21_669, 21_668, 21_667]}
          ] do
        actual =
          entry
          |> CreatureScript.events()
          |> Enum.filter(&(&1.event_type == :timer_in_combat))
          |> Enum.flat_map(&List.flatten(&1.actions))
          |> Enum.map(& &1.datalong)

        assert actual == spells
      end
    end

    test "both ritual events forward to the correct nearby summoner" do
      for {event, summoner} <- [{7_060, 13_236}, {7_268, 13_442}] do
        assert [
                 %ScriptStep{
                   command: :send_script_event,
                   datalong: ^event,
                   target_type: :nearest_creature_with_entry,
                   target_param1: ^summoner,
                   target_param2: 40,
                   swap_final?: true
                 }
               ] = EventScript.steps_by_event()[event]
      end
    end
  end

  defp route(entry), do: Enum.find(AlteracValleyAssault.routes(), &(&1.entry == entry))

  defp phase(phase) do
    blackboard = Blackboard.new()
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}
  end

  defp creature(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, flags: 0x101, auras: []},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.0}},
      internal: %Internal{
        world: WorldRef.instance(30, Unique.integer()),
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}}
      }
    }
  end
end
