defmodule ThistleTea.Game.World.Entity.ScriptSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Waypoints
  alias ThistleTea.Game.Core.AI.BT.Mob.Spells
  alias ThistleTea.Game.Core.AI.CreatureSpell
  alias ThistleTea.Game.Core.AI.CreatureSpellList
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Waypoint
  alias ThistleTea.Game.Core.Entity.Component.Internal.WaypointRoute
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.ScriptSpells

  describe "prepare/4" do
    test "prepares every candidate of a received spell-list command" do
      spell = %Spell{id: 29_931, cast_time_ms: 0, range_yards: 0.0, mana_cost: 0, power_type: 0, effects: []}
      first = %CreatureSpellList{id: 1, spells: [%CreatureSpell{spell_id: spell.id, cast_target: :self}]}
      second = %CreatureSpellList{id: 2, spells: [%CreatureSpell{spell_id: 20, cast_target: :self}]}

      step = %ScriptStep{
        command: :creature_spells,
        datalong: 1,
        datalong2: 2,
        dataint: 50,
        dataint2: 50,
        creature_spell_lists: %{1 => first, 2 => second}
      }

      prepared = ScriptSpells.prepare(mob(), [step], Waypoints.empty(), fn id -> %{spell | id: id} end)
      assert Map.keys(prepared.internal.spellbook) |> Enum.sort() == [20, 29_931]
      {changed, memory} = Script.run(prepared, Blackboard.new(), [step], 0, Context.new(0))
      assert {:failure, cast, _memory} = Spells.try_cast(changed, memory, Context.new(0))
      assert Enum.any?(cast.internal.events, &match?(%Effects.SpellGo{spell_id: 29_931}, &1))
      assert ScriptSpells.prepare(prepared, [step], Waypoints.empty(), fn _ -> flunk("already loaded") end) == prepared
    end

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
