defmodule ThistleTea.Game.Core.AI.CreatureScript.RiggleBassbaitTest do
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

  @riggle 15_077
  @master_angler 8_193
  @tournament 15
  @announce_begin 30_022
  @announce_over 30_023
  @has_winner 30_056
  @gossip 0x1
  @taking_turn_ins 0x3

  describe "CreatureScript registry" do
    test "ports Riggle Bassbait and his Master Angler turn-in" do
      assert CreatureScript.ported?(@riggle)
      assert Map.has_key?(CreatureScript.quest_end_steps(), @master_angler)
    end
  end

  describe "events/1" do
    test "a Riggle who arrives before the tournament starts a fresh week" do
      last_week = %{@has_winner => 1, @announce_over => 0}

      assert spawned([], last_week) == %{@has_winner => 0, @announce_over => 0, @announce_begin => 1}
    end

    test "a Riggle respawned mid-tournament repeats nothing" do
      assert spawned([@tournament], %{@announce_over => 1}) == %{}
      assert spawned([@tournament], %{@has_winner => 1}) == %{}
    end

    test "a Riggle who arrives on a fresh server mid-tournament still opens it" do
      assert spawned([@tournament], %{}) == %{@announce_begin => 1}
    end

    test "the tournament opens once to the zone and takes turn-ins" do
      {riggle, variables, talk} = judge(@gossip, [@tournament], %{@announce_begin => 1})

      assert riggle.unit.npc_flags == @taking_turn_ins
      assert variables == %{@announce_begin => 0, @announce_over => 1}
      assert talk == ["10608"]

      assert {%Mob{unit: %Unit{npc_flags: @taking_turn_ins}}, %{}, []} =
               judge(@taking_turn_ins, [@tournament], %{@announce_over => 1})
    end

    test "a winner closes the week's turn-ins without another yell" do
      {riggle, variables, talk} = judge(@taking_turn_ins, [@tournament], %{@has_winner => 1})

      assert riggle.unit.npc_flags == @gossip
      assert {variables, talk} == {%{}, []}
    end

    test "the tastyfish leave with one last yell" do
      {riggle, variables, talk} = judge(@taking_turn_ins, [], %{@announce_over => 1})

      assert riggle.unit.npc_flags == @gossip
      assert variables == %{@announce_over => 0}
      assert talk == ["10609"]

      assert {_riggle, %{}, []} = judge(@gossip, [], %{@announce_over => 0})
    end
  end

  describe "quest_end_steps/0" do
    test "the first Master Angler wins the week and is named to the zone" do
      angler = Guid.from_low_guid(:player, Unique.integer())
      steps = Map.fetch!(CreatureScript.quest_end_steps(), @master_angler)

      {riggle, variables} = run(steps, riggle(@taking_turn_ins), [@tournament], %{}, angler)

      assert riggle.unit.npc_flags == @gossip
      assert variables == %{@has_winner => 1}
      assert [%Effects.MonsterTalk{text: "10610", target_guid: ^angler}] = talks(riggle)
    end
  end

  defp spawned(active_events, saved) do
    {_riggle, variables} = @riggle |> event(:spawned) |> run(riggle(@gossip), active_events, saved)
    variables
  end

  defp judge(npc_flags, active_events, saved) do
    {riggle, variables} = @riggle |> event(:timer_ooc) |> run(riggle(npc_flags), active_events, saved)
    {%{riggle | internal: %{riggle.internal | events: []}}, variables, Enum.map(talks(riggle), & &1.text)}
  end

  defp run(steps, riggle, active_events, saved, target \\ nil) do
    context = context(active_events, saved)
    {riggle, blackboard} = Script.run(riggle, Blackboard.new(), with_texts(steps), target, context)
    settle(riggle, blackboard, active_events, saved, %{}, [])
  end

  defp settle(riggle, blackboard, active_events, saved, written, kept) do
    {commands, others} = Enum.split_with(riggle.internal.events, &is_struct(&1, Effects.ScriptedEventCommand))
    riggle = %{riggle | internal: %{riggle.internal | events: []}}

    case commands do
      [] ->
        {%{riggle | internal: %{riggle.internal | events: kept ++ others}}, written}

      _ ->
        written = Enum.reduce(commands, written, &Map.put(&2, &1.step.datalong, &1.step.datalong2))
        context = context(active_events, Map.merge(saved, written))

        {riggle, blackboard} =
          Enum.reduce(commands, {riggle, blackboard}, fn %{reply: {id, receipt, world}}, {riggle, blackboard} ->
            Run.resume(riggle, blackboard, id, receipt, world, :continue, context)
          end)

        settle(riggle, blackboard, active_events, saved, written, kept ++ others)
    end
  end

  defp context(active_events, saved),
    do: Context.new(0, active_game_events: MapSet.new(active_events), saved_variables: saved)

  defp event(entry, type) do
    entry |> CreatureScript.events() |> Enum.find(&(&1.event_type == type)) |> Map.fetch!(:actions) |> hd()
  end

  defp with_texts(steps) do
    Enum.map(steps, fn
      %ScriptStep{command: :talk, dataint: id} = step ->
        %{step | texts: [%{text: Integer.to_string(id), chat_type: :zone_yell, language: 0, emote_id: 0}]}

      %ScriptStep{sub_scripts: sub_scripts} = step ->
        %{step | sub_scripts: Map.new(sub_scripts, fn {id, steps} -> {id, with_texts(steps)} end)}
    end)
  end

  defp talks(%Mob{internal: %Internal{events: events}}), do: Enum.filter(events, &is_struct(&1, Effects.MonsterTalk))

  defp riggle(npc_flags) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @riggle, Unique.integer()), entry: @riggle},
      unit: %Unit{health: 100, max_health: 100, level: 55, npc_flags: npc_flags, flags: 0, auras: []},
      movement_block: %MovementBlock{position: {-14_440.0, 480.0, 15.0, 0.0}},
      internal: %Internal{world: %WorldRef{map_id: 0}, name: "Riggle Bassbait", creature: %Creature{}}
    }
  end
end
