defmodule ThistleTea.Game.ScriptFailureVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.AIEvent
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.EventAI
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  describe "loaded result-checked events" do
    test "Goretusk retries its one-shot charge after cast failure" do
      row = Mangos.Repo.get!(Mangos.CreatureAiEvent, 15_701)
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [row.action1_script])
      event = AIEvent.build(row, scripts)
      assert event.event_type == :range
      assert event.check_result?
      refute event.repeatable?
      assert [[step]] = event.actions
      assert step.abort_on_failure?
      assert step.target_self?
      assert step.datalong == 6_268

      target = Guid.from_low_guid(:player, 2)
      spell = %Spell{id: 6_268, mana_cost: 20, power_type: 0, cast_time_ms: 0, effects: []}

      mob = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 157, 1), entry: 157},
        unit: %Unit{health: 100, max_health: 100, target: target, power_type: 0, power1: 0, max_power1: 100},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          world: WorldRef.open(0),
          in_combat: true,
          creature: %Creature{ai_events: [event]},
          spellbook: %{spell.id => spell}
        }
      }

      observation = %Observation{guid: target, distance: 10.0}
      perception = Context.Perception.new(0, nil, %{target => observation}, %{mobs: [], players: [], game_objects: []})
      {failed, blackboard} = EventAI.tick(mob, Blackboard.new(), 0, Context.new(0, perception: perception))
      assert failed.internal.events == []
      refute MapSet.member?(blackboard.event_ai.disabled, 0)
      assert blackboard.event_ai.timers[0] == 0

      ready = %{failed | unit: %{failed.unit | power1: 100}}
      context = Context.new(1_000, perception: perception)
      {casted, blackboard} = EventAI.tick(ready, blackboard, 1_000, context)
      assert Enum.any?(casted.internal.events, &match?(%Effects.SpellGo{spell_id: 6_268}, &1))
      assert MapSet.member?(blackboard.event_ai.disabled, 0)
    end
  end
end
