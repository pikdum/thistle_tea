defmodule ThistleTea.Game.Core.AI.CreatureScript.FelwoodOozeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
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

  @cursed_ooze 7_086
  @tainted_ooze 7_092

  describe "events/1" do
    test "each ooze casts its own aura in combat" do
      for {entry, aura} <- [{@cursed_ooze, 13_483}, {@tainted_ooze, 3_335}] do
        [timer, _jar] = CreatureScript.events(entry)

        assert %{event_type: :timer_in_combat, param1: 3_000, param2: 3_000, param3: 60_000, param4: 60_000} = timer
        assert [[%ScriptStep{command: :cast_spell, datalong: ^aura, target_self?: true}]] = timer.actions
      end
    end

    test "jarring a dead ooze despawns its remains" do
      player = Guid.from_low_guid(:player, Unique.integer())
      ooze = ooze(@cursed_ooze)

      {ooze, _blackboard} = EventAI.on_spell_hit(ooze, Blackboard.new(), player, 15_699, 0, Context.new(0))
      assert ooze.internal.events == []

      {ooze, _blackboard} = EventAI.on_spell_hit(ooze, Blackboard.new(), player, 15_698, 0, Context.new(0))
      assert [%Effects.DespawnSelf{duration_ms: 0}] = ooze.internal.events
    end
  end

  defp ooze(entry) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 0, max_health: 3_000, level: 50, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Cursed Ooze",
        creature: %Creature{ai_events: CreatureScript.events(entry)}
      }
    }
  end
end
