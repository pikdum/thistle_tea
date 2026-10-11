defmodule ThistleTea.Game.Core.AI.EventAIPauseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Random
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "tick/4" do
    test "pauses only opted-in timers, including between event checks and with negative time" do
      for start <- [0, -20_000] do
        mob = mob([timer("paused", true), timer("ordinary", false)])
        {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), mob.unit.target, start, context(start))
        mob = stun(mob)
        {mob, blackboard} = tick(mob, blackboard, start + 500)
        assert talks(mob) == []
        {mob, blackboard} = tick(mob, blackboard, start + 1_000)
        assert talks(mob) == []
        {mob, blackboard} = tick(mob, blackboard, start + 10_000)
        assert talks(mob) == ["ordinary"]
        mob = %{mob | unit: %{mob.unit | auras: []}}
        {mob, blackboard} = tick(mob, blackboard, start + 11_000)
        assert talks(mob) == []
        {mob, _blackboard} = tick(mob, blackboard, start + 12_000)
        assert talks(mob) == ["paused"]
      end
    end

    test "preserves the remaining repeat cooldown across a stun" do
      mob = mob([timer("paused", true)])
      {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), mob.unit.target, 0, context(0))
      {mob, blackboard} = tick(mob, blackboard, 2_000)
      assert talks(mob) == ["paused"]
      mob = stun(mob)
      {mob, blackboard} = tick(mob, blackboard, 6_000)
      assert talks(mob) == []
      mob = %{mob | unit: %{mob.unit | auras: []}}
      {mob, blackboard} = tick(mob, blackboard, 10_000)
      assert talks(mob) == []
      {mob, _blackboard} = tick(mob, blackboard, 11_000)
      assert talks(mob) == ["paused"]
    end

    test "a new pull resets the timer clock after an idle gap" do
      mob = mob([timer("paused", true)])
      {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), mob.unit.target, 0, context(0))
      {mob, blackboard} = tick(mob, blackboard, 1_000)
      {mob, blackboard} = EventAI.on_evade(mob, blackboard, 1_000, context(1_000))
      {mob, blackboard} = EventAI.enter_combat(mob, blackboard, mob.unit.target, 50_000, context(50_000))
      mob = stun(mob)
      {mob, blackboard} = tick(mob, blackboard, 51_000)
      assert talks(mob) == []
      mob = %{mob | unit: %{mob.unit | auras: []}}
      {mob, blackboard} = tick(mob, blackboard, 52_000)
      assert talks(mob) == []
      {mob, _blackboard} = tick(mob, blackboard, 53_000)
      assert talks(mob) == ["paused"]
    end
  end

  defp timer(text, pause?) do
    %AIEvent{
      id: Unique.integer(),
      event_type: :timer_in_combat,
      repeatable?: true,
      pause_while_stunned?: pause?,
      param1: 2_000,
      param2: 2_000,
      param3: 5_000,
      param4: 5_000,
      actions: [[%ScriptStep{command: :talk, texts: [%{text: text, chat_type: :say, language: 0, emote_id: 0}]}]]
    }
  end

  defp mob(events) do
    entry = Unique.integer()

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 100, max_health: 100, target: Unique.integer(), auras: []},
      internal: %Internal{
        world: WorldRef.instance(409, Unique.integer()),
        in_combat: true,
        creature: %Creature{ai_events: events}
      }
    }
  end

  defp stun(mob), do: %{mob | unit: %{mob.unit | auras: [%Holder{auras: [%Aura{type: :mod_stun}]}]}}

  defp context(now), do: Context.new(now, random: Random.fixed())

  defp tick(mob, blackboard, now) do
    mob = %{mob | internal: %{mob.internal | events: []}}
    EventAI.tick(mob, blackboard, now, context(now))
  end

  defp talks(mob), do: for(%Effects.MonsterTalk{text: text} <- mob.internal.events, do: text)
end
