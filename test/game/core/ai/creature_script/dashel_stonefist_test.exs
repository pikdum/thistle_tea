defmodule ThistleTea.Game.Core.AI.CreatureScript.DashelStonefistTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.Script.Run
  alias ThistleTea.Game.Core.AI.ScriptStep
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

  @dashel 4_961
  @thug 4_969
  @missing_diplomat 1_447
  @brawler 189
  @friendly_to_all 35

  setup do
    %{dashel: dashel(), player: Guid.from_low_guid(:player, Unique.integer())}
  end

  describe "quest_start_steps/0" do
    test "accepting the quest turns Dashel and two thugs on the player", %{dashel: dashel, player: player} do
      steps = Map.fetch!(CreatureScript.quest_start_steps(), @missing_diplomat)
      {dashel, blackboard} = dashel |> Script.run(Blackboard.new(), steps, player, Context.new(0)) |> replied()

      assert dashel.unit.faction_template == @brawler
      assert dashel.unit.npc_flags == 0
      assert dashel.internal.invincibility_health_threshold == 200
      assert blackboard.event_ai.phase == 1

      assert [%Effects.SummonCreature{}, %Effects.SummonCreature{}] = summons = of(dashel, Effects.SummonCreature)
      assert Enum.all?(summons, &(&1.summon.entry == @thug and &1.summon.attack_guid == player))
      assert [%Effects.StartAttack{target_guid: ^player}] = of(dashel, Effects.StartAttack)
    end
  end

  describe "events/1" do
    test "he gives up only during the quest fight" do
      [give_up, fail, died, thugs_home, alone] = CreatureScript.events(@dashel)

      assert %{event_type: :hp, param1: 20} = give_up
      assert %{event_type: :evade} = fail
      assert %{event_type: :death} = died
      assert %{event_type: :reached_home, condition: %{reverse?: false}} = thugs_home
      assert %{event_type: :reached_home, condition: %{reverse?: true}} = alone
      assert in_phase?(give_up, 1) and not in_phase?(give_up, 0)
      assert in_phase?(fail, 1) and not in_phase?(fail, 2)
      assert in_phase?(thugs_home, 2) and not in_phase?(thugs_home, 1)
    end

    test "giving up befriends everyone and sends Dashel home", %{dashel: dashel, player: player} do
      [give_up | _events] = CreatureScript.events(@dashel)
      blackboard = put_in(Blackboard.new().event_ai.phase, 1)

      {dashel, blackboard} =
        dashel |> Script.run(blackboard, List.flatten(give_up.actions), player, Context.new(0)) |> replied()

      assert dashel.unit.faction_template == @friendly_to_all
      assert blackboard.event_ai.phase == 2
      assert [%Effects.EnterEvade{}] = of(dashel, Effects.EnterEvade)
    end

    test "each thug answers Dashel in its own turn" do
      [first, second] = CreatureScript.events(@thug)

      assert %{event_type: :script_event, param1: 1} = first
      assert in_phase?(first, 1) and not in_phase?(first, 2)
      assert in_phase?(second, 2) and not in_phase?(second, 1)
      assert talk(first) == 1_716
      assert talk(second) == 1_715
    end

    test "the quest completes for the player kept by the map event once he settles" do
      [_give_up, _fail, _died, _thugs_home, alone] = CreatureScript.events(@dashel)

      assert %ScriptStep{command: :quest_explored, datalong: @missing_diplomat, target_type: :map_event_target} =
               alone.actions |> List.flatten() |> nested() |> Enum.find(&(&1.command == :quest_explored))
    end
  end

  defp replied({mob, blackboard}) do
    case Enum.find(mob.internal.events, &match?(%Effects.ScriptedEventCommand{reply: {_id, _receipt, _world}}, &1)) do
      nil ->
        {mob, blackboard}

      %{reply: {id, receipt, world}} = command ->
        mob = %{mob | internal: %{mob.internal | events: List.delete(mob.internal.events, command)}}
        mob |> Run.resume(blackboard, id, receipt, world, :continue, Context.new(0)) |> replied()
    end
  end

  defp in_phase?(event, phase), do: Bitwise.band(event.inverse_phase_mask, Bitwise.bsl(1, phase)) == 0

  defp talk(event) do
    event.actions |> List.flatten() |> nested() |> Enum.find_value(&(&1.command == :talk and &1.dataint))
  end

  defp nested(steps), do: Enum.flat_map(steps, &[&1 | nested(Enum.flat_map(Map.values(&1.sub_scripts), fn s -> s end))])

  defp of(mob, struct), do: Enum.filter(mob.internal.events, &(&1.__struct__ == struct))

  defp dashel do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @dashel, Unique.integer()), entry: @dashel},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        level: 30,
        auras: [],
        flags: 0,
        npc_flags: 2,
        faction_template: 122
      },
      movement_block: %MovementBlock{position: {-8_681.22, 432.526, 99.301, 1.658}},
      internal: %Internal{
        world: %WorldRef{map_id: 0},
        name: "Dashel Stonefist",
        creature: %Creature{ai_events: CreatureScript.events(@dashel)}
      }
    }
  end
end
