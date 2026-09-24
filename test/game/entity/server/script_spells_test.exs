defmodule ThistleTea.Game.Entity.Server.ScriptSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Waypoint
  alias ThistleTea.Game.Entity.Data.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.ScriptSpells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  describe "prepare/4" do
    test "an externally supplied cast reaches the ordinary casting pipeline" do
      spell = %Spell{id: 29_931, cast_time_ms: 0, range_yards: 0.0, mana_cost: 0, power_type: 0, effects: []}
      step = %ScriptStep{command: :cast_spell, datalong: spell.id, target_self?: true}
      mob = mob()
      {unprepared, _} = Script.run(mob, Blackboard.new(), [step], 1, Context.new(0))
      assert unprepared.internal.events == []

      prepared = ScriptSpells.prepare(mob, [step], Waypoints.empty(), fn 29_931 -> spell end)
      {cast, _} = Script.run(prepared, Blackboard.new(), [step], 1, Context.new(0))
      assert Enum.any?(cast.internal.events, &match?(%Effects.SpellGo{spell_id: 29_931}, &1))
      assert prepared.internal.creature.spells == []
      assert ScriptSpells.prepare(prepared, [step], Waypoints.empty(), fn _ -> flunk("already loaded") end) == prepared
    end

    test "prepares nested route spells while guarding repeated route starts" do
      start = %ScriptStep{command: :start_waypoints, datalong: 3, dataint2: 18_039}
      cast = %ScriptStep{command: :cast_spell, datalong: 24_221}
      nested = %ScriptStep{command: :start_script, sub_scripts: %{1 => [cast, start]}}
      route = %WaypointRoute{points: %{1 => %Waypoint{script_steps: [nested]}}}
      waypoints = Waypoints.new(%{{:special, 18_039} => route})
      prepared = ScriptSpells.prepare(mob(), [start], waypoints, fn 24_221 -> %Spell{id: 24_221} end)
      assert Map.keys(prepared.internal.spellbook) == [24_221]
    end

    test "skips missing spells without replacing the existing spellbook" do
      mob = mob()
      spellbook = %{1 => %Spell{id: 1}}
      mob = %{mob | internal: %{mob.internal | spellbook: spellbook}}

      prepared =
        ScriptSpells.prepare(mob, [%ScriptStep{command: :cast_spell, datalong: 2}], Waypoints.empty(), fn _ -> nil end)

      assert prepared.internal.spellbook == spellbook
    end
  end

  defp mob do
    %Mob{
      object: %Object{guid: 1, entry: 17_209},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [], flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), creature: %Creature{}, spellbook: %{}}
    }
  end
end
