defmodule ThistleTea.Game.Core.AI.CreatureScript.SicklyCritterTest do
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

  @sickly_deer 12_298
  @sickly_gazelle 12_296
  @apply_salve 19_512

  setup [:critter]

  describe "CreatureScript" do
    test "replaces both sickly critters' EventAI with the port" do
      assert CreatureScript.ported?(@sickly_deer)
      assert CreatureScript.ported?(@sickly_gazelle)
      refute CreatureScript.ported?(12_299)
    end

    test "names the cured entries so their archetypes are preloaded" do
      assert Enum.sort(CreatureScript.creature_entries()) == [12_297, 12_299]
    end
  end

  describe "events/1" do
    test "a salved critter flees, despawns, and is cured once", %{critter: critter, druid: druid} do
      {critter, blackboard} = EventAI.on_spell_hit(critter, Blackboard.new(), druid, 1, 0, Context.new(0))
      assert critter.internal.events == []

      {critter, blackboard} = EventAI.on_spell_hit(critter, blackboard, druid, @apply_salve, 0, Context.new(0))

      assert blackboard.event_ai.phase == 1
      assert {blackboard.combat.flee_from, blackboard.combat.flee_until} == {druid, 10_000}

      assert [
               %Effects.DespawnSelf{duration_ms: 10_000, respawn_delay_ms: 0},
               %Effects.ScriptSteps{duration_ms: 1_500, target_guid: ^druid, steps: steps}
             ] = critter.internal.events

      assert [
               %ScriptStep{command: :update_entry, datalong: 12_299},
               %ScriptStep{command: :remove_aura, datalong: 19_502},
               %ScriptStep{command: :cast_credit, datalong: @apply_salve}
             ] = steps

      critter = %{critter | internal: %{critter.internal | events: []}}
      {critter, _blackboard} = EventAI.on_spell_hit(critter, blackboard, druid, @apply_salve, 100, Context.new(100))
      assert critter.internal.events == []
    end

    test "a sickly gazelle becomes a cured gazelle" do
      [%{actions: [steps]}] = CreatureScript.events(@sickly_gazelle)
      %ScriptStep{sub_scripts: scripts} = Enum.find(steps, &(&1.command == :start_script))

      assert %ScriptStep{datalong: 12_297} =
               scripts |> Map.values() |> List.flatten() |> Enum.find(&(&1.command == :update_entry))
    end
  end

  defp critter(_context) do
    critter = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @sickly_deer, Unique.integer()), entry: @sickly_deer},
      unit: %Unit{health: 100, max_health: 100, level: 5, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: %WorldRef{map_id: 1},
        name: "Sickly Deer",
        creature: %Creature{ai_events: CreatureScript.events(@sickly_deer), critter?: true}
      }
    }

    %{critter: critter, druid: Guid.from_low_guid(:player, Unique.integer())}
  end
end
