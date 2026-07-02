defmodule ThistleTea.Game.Entity.Logic.AI.EventAITest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Guid

  @talk_step %ScriptStep{command: :talk, texts: [%{text: "!", chat_type: :say, language: 0, emote_id: 0}]}

  describe "on_spawned/3" do
    test "fires spawned events" do
      mob = mob(events: [event(:spawned)])

      {mob, _blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "respects the inverse phase mask" do
      mob = mob(events: [event(:spawned, inverse_phase_mask: 0b1)])

      {mob, _blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)

      assert mob.internal.events == []
    end
  end

  describe "on_reached_home/3" do
    test "fires reached_home events" do
      mob = mob(events: [event(:reached_home)])

      {mob, _blackboard} = EventAI.on_reached_home(mob, Blackboard.new(), 0)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end
  end

  describe "conditions" do
    test "an event with a failing db_guid condition does not fire" do
      condition = %Condition{type: :db_guid, value1: 12_345}
      mob = mob(events: [event(:spawned, condition: condition)], db_guid: 99)

      {mob, _blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)

      assert mob.internal.events == []
    end

    test "an event with a matching db_guid condition fires" do
      condition = %Condition{type: :db_guid, value1: 99}
      mob = mob(events: [event(:spawned, condition: condition)], db_guid: 99)

      {mob, _blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "a failing condition leaves the repeat timer unconsumed" do
      condition = %Condition{type: :db_guid, value1: 12_345}

      ooc_event =
        event(:timer_ooc,
          param1: 1_000,
          param2: 1_000,
          param3: 60_000,
          param4: 60_000,
          repeatable?: true,
          condition: condition
        )

      mob = mob(events: [ooc_event], db_guid: 99)

      {mob, blackboard} = EventAI.tick(mob, Blackboard.new(), 0)
      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, blackboard} = EventAI.tick(mob, blackboard, 1_100)
      assert mob.internal.events == []
      assert blackboard.eventai_timers == %{0 => 1_000}
    end
  end

  describe "tick/3" do
    test "fires hp events within bounds and disables non-repeatable ones" do
      mob = mob(events: [event(:hp, param1: 15, param2: 0)], in_combat: true, health: 10)

      {mob, blackboard} = EventAI.tick(mob, Blackboard.new(), 1_000)
      assert [%Event{type: :monster_talk}] = mob.internal.events

      mob = clear_events(mob)
      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, _blackboard} = EventAI.tick(mob, blackboard, 3_000)
      assert mob.internal.events == []
    end

    test "skips hp events above the threshold" do
      mob = mob(events: [event(:hp, param1: 15, param2: 0)], in_combat: true, health: 90)

      {mob, _blackboard} = EventAI.tick(mob, Blackboard.new(), 1_000)

      assert mob.internal.events == []
    end

    test "runs out-of-combat timers from their initial delay and repeats" do
      ooc_event = event(:timer_ooc, param1: 1_000, param2: 1_000, param3: 5_000, param4: 5_000, repeatable?: true)
      mob = mob(events: [ooc_event])

      {mob, blackboard} = EventAI.tick(mob, Blackboard.new(), 0)
      assert mob.internal.events == []

      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, blackboard} = EventAI.tick(mob, blackboard, 1_100)
      assert [%Event{type: :monster_talk}] = mob.internal.events

      mob = clear_events(mob)
      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, blackboard} = EventAI.tick(mob, blackboard, 2_000)
      assert mob.internal.events == []

      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, _blackboard} = EventAI.tick(mob, blackboard, 6_200)
      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "does not run out-of-combat timers while in combat" do
      mob =
        mob(
          events: [event(:timer_ooc, param1: 0, param2: 0, param3: 0, param4: 0, repeatable?: true)],
          in_combat: true
        )

      {mob, _blackboard} = EventAI.tick(mob, Blackboard.new(), 1_000)

      assert mob.internal.events == []
    end
  end

  describe "enter_combat/4" do
    test "fires aggro events and re-enables fired events" do
      enemy = Guid.from_low_guid(:player, 3)
      mob = mob(events: [event(:aggro), event(:spawned)])

      {mob, blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)
      assert [%Event{type: :monster_talk}] = mob.internal.events
      mob = clear_events(mob)

      {mob, blackboard} = EventAI.enter_combat(mob, blackboard, enemy, 100)
      assert [%Event{type: :monster_talk}] = mob.internal.events
      assert blackboard.eventai_disabled == MapSet.new([0])

      mob = clear_events(mob)
      {mob, _blackboard} = EventAI.on_spawned(mob, blackboard, 200)
      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "rolls in-combat timers from their initial params" do
      enemy = Guid.from_low_guid(:player, 3)

      mob =
        mob(
          events: [event(:timer_in_combat, param1: 2_000, param2: 2_000, param3: 0, param4: 0, repeatable?: true)],
          in_combat: true
        )

      {mob, blackboard} = EventAI.enter_combat(mob, Blackboard.new(), enemy, 0)
      assert mob.internal.events == []

      {mob, blackboard} = EventAI.tick(mob, blackboard, 1_000)
      assert mob.internal.events == []

      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, _blackboard} = EventAI.tick(mob, blackboard, 2_100)
      assert [%Event{type: :monster_talk}] = mob.internal.events
    end
  end

  describe "on_evade/3" do
    test "fires evade events and re-initializes out-of-combat timers" do
      mob =
        mob(
          events: [
            event(:evade),
            event(:timer_ooc, param1: 1_000, param2: 1_000, param3: 0, param4: 0, repeatable?: true)
          ]
        )

      {mob, blackboard} = EventAI.on_spawned(mob, Blackboard.new(), 0)
      {mob, blackboard} = EventAI.on_evade(mob, blackboard, 10_000)

      assert [%Event{type: :monster_talk}] = mob.internal.events
      assert blackboard.eventai_timers[1] == 11_000
      mob = clear_events(mob)

      blackboard = %{blackboard | next_eventai_at: 0}
      {mob, _blackboard} = EventAI.tick(mob, blackboard, 11_100)
      assert [%Event{type: :monster_talk}] = mob.internal.events
    end
  end

  describe "on_spell_hit/5" do
    test "matches the spell id filter" do
      caster = Guid.from_low_guid(:player, 3)
      mob = mob(events: [event(:hit_by_spell, param1: 116)])

      {mob, blackboard} = EventAI.on_spell_hit(mob, Blackboard.new(), caster, 133, 0)
      assert mob.internal.events == []

      {mob, _blackboard} = EventAI.on_spell_hit(mob, blackboard, caster, 116, 0)
      assert [%Event{type: :monster_talk, target_guid: ^caster}] = mob.internal.events
    end
  end

  describe "on_kill/4" do
    test "skips player-only kill events for creature victims" do
      mob_victim = Guid.from_low_guid(:mob, 90, 2)
      player_victim = Guid.from_low_guid(:player, 3)
      mob = mob(events: [event(:kill, param3: 1, repeatable?: true)])

      {mob, blackboard} = EventAI.on_kill(mob, Blackboard.new(), mob_victim, 0)
      assert mob.internal.events == []

      {mob, _blackboard} = EventAI.on_kill(mob, blackboard, player_victim, 0)
      assert [%Event{type: :monster_talk}] = mob.internal.events
    end
  end

  describe "negative monotonic now (regression)" do
    # BEAM monotonic time is negative on many systems; timerless timed events and
    # all edge events default to a nil timer and must still be considered "due".
    @negative_now -576_458_921_014

    test "hp event fires at low health with a negative now" do
      mob = mob(events: [event(:hp, param1: 15, param2: 0)], in_combat: true, health: 10)

      {mob, _blackboard} = EventAI.tick(mob, Blackboard.new(), @negative_now)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "aggro edge event fires on combat entry with a negative now" do
      enemy = Guid.from_low_guid(:player, 3)
      mob = mob(events: [event(:aggro)])

      {mob, _blackboard} = EventAI.enter_combat(mob, Blackboard.new(), enemy, @negative_now)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end

    test "spawned edge event fires with a negative now" do
      mob = mob(events: [event(:spawned)])

      {mob, _blackboard} = EventAI.on_spawned(mob, Blackboard.new(), @negative_now)

      assert [%Event{type: :monster_talk}] = mob.internal.events
    end
  end

  defp event(event_type, opts \\ []) do
    %AIEvent{
      id: System.unique_integer([:positive]),
      event_type: event_type,
      chance: 100,
      repeatable?: Keyword.get(opts, :repeatable?, false),
      inverse_phase_mask: Keyword.get(opts, :inverse_phase_mask, 0),
      param1: Keyword.get(opts, :param1, 0),
      param2: Keyword.get(opts, :param2, 0),
      param3: Keyword.get(opts, :param3, 0),
      param4: Keyword.get(opts, :param4, 0),
      condition: Keyword.get(opts, :condition),
      actions: [[@talk_step]]
    }
  end

  defp mob(opts) do
    health = Keyword.get(opts, :health, 100)

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 589, 1)},
      unit: %Unit{health: health, max_health: 100, level: 14, target: 0, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        map: 0,
        name: "Defias Pillager",
        in_combat: Keyword.get(opts, :in_combat, false),
        creature: %Creature{ai_events: Keyword.fetch!(opts, :events), db_guid: Keyword.get(opts, :db_guid)},
        spellbook: %{}
      }
    }
  end

  defp clear_events(%Mob{internal: %Internal{} = internal} = mob) do
    %{mob | internal: %{internal | events: []}}
  end
end
