defmodule ThistleTea.Game.Entity.Logic.AI.CreatureSpellListTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.CreatureSpellList
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob.Spells
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "execute_steps/5" do
    test "switches casts and starts fresh timers at assignment", %{mob: mob, list: list} do
      memory = %Blackboard{
        spells: %Blackboard.Spells{timers: %{0 => 100_000}, next_list_at: 100_000, combat_movement: false}
      }

      {changed, memory} = Script.execute_steps(mob, memory, [step(list)], 0, context(1_000))
      assert memory.spells.list == list
      assert memory.spells.timers == %{0 => 3_000}
      assert memory.spells.combat_movement == false
      assert changed.internal.creature.spells == mob.internal.creature.spells
      assert {:failure, waiting, memory} = Spells.try_cast(changed, memory, context(2_999))
      assert waiting.internal.events == []
      assert {:failure, cast, _memory} = Spells.try_cast(changed, memory, context(4_199))
      assert Enum.any?(cast.internal.events, &match?(%Effects.SpellGo{spell_id: 20}, &1))
      refute Enum.any?(cast.internal.events, &match?(%Effects.SpellStart{spell_id: 10}, &1))
    end

    test "reassigning the same list rerolls its initial delays", %{mob: mob, list: list} do
      {mob, memory} = Script.execute_steps(mob, Blackboard.new(), [step(list)], 0, context(1_000))
      {_mob, memory} = Script.execute_steps(mob, memory, [step(list)], 0, context(5_000, 501))
      assert memory.spells.timers == %{0 => 7_500}
    end

    test "clearing leaves the active cast intact and prevents later list casts", %{mob: mob, list: list} do
      casting = Casting.start(mob, %{mob.internal.spellbook[10] | cast_time_ms: 5_000}, Target.unit(mob.object.guid), 0)
      {changed, memory} = Script.execute_steps(casting, Blackboard.new(), [step(list), clear()], 0, context(1_000))
      assert changed.internal.casting == casting.internal.casting
      refute Spells.has_spells?(changed, memory)
      assert memory.spells.timers == %{}
      changed = %{changed | internal: %{changed.internal | blackboard: memory}}
      finished = Casting.complete(changed, 5_000)
      assert Enum.any?(finished.internal.events, &match?(%Effects.SpellGo{spell_id: 10}, &1))
      assert finished.internal.blackboard.spells.list.id == 0
    end

    test "uses absolute percentage intervals and clears on an uncovered roll", %{mob: mob, list: list} do
      other = %{list | id: 3}

      step = %{
        step(list)
        | datalong2: 0,
          datalong3: 3,
          dataint: 33,
          dataint2: 33,
          dataint3: 20,
          creature_spell_lists: %{2 => list, 3 => other}
      }

      for {roll, expected} <- [{1, 2}, {33, 2}, {34, 0}, {66, 0}, {67, 3}, {86, 3}, {87, 0}, {100, 0}] do
        {_mob, memory} = Script.execute_steps(mob, Blackboard.new(), [step], 0, context(0, roll))
        assert memory.spells.list.id == expected
      end
    end

    test "missing definitions preserve the current list", %{mob: mob, list: list} do
      {mob, memory} = Script.execute_steps(mob, Blackboard.new(), [step(list)], 0, context(0))
      missing = %{step(list) | datalong: 999, abort_on_failure?: true}
      {_mob, unchanged} = Script.execute_steps(mob, memory, [missing], 0, context(4_000))
      assert unchanged.spells == memory.spells
    end

    test "non-creature sources honor the abort flag", %{mob: mob, list: list} do
      player = %Character{object: mob.object, unit: mob.unit, internal: mob.internal}

      for abort? <- [true, false] do
        steps = [%{step(list) | abort_on_failure?: abort?}, %ScriptStep{command: :stand_state, datalong: 1}]
        {changed, _} = Script.execute_steps(player, Blackboard.new(), steps, 0, context(0))
        assert changed.unit.stand_state == if(abort?, do: 0, else: 1)
      end
    end
  end

  describe "combat lifecycle" do
    test "combat stop and respawn restore the template list", %{mob: mob, list: list} do
      {changed, memory} = Script.execute_steps(mob, Blackboard.new(), [step(list)], 0, context(0))
      changed = %{changed | internal: %{changed.internal | blackboard: memory, in_combat: true}}

      for result <- [Engagement.leave(changed, :evade), Engagement.die(changed), Engagement.reset(changed)] do
        memory = Blackboard.ensure(result.entity.internal.blackboard)
        assert memory.spells.list == nil
        assert memory.spells.timers == nil
        assert Spells.entries(result.entity, memory) == mob.internal.creature.spells
      end
    end
  end

  describe "observation_radius/1" do
    test "observes friendly targets required by the replacement list", %{mob: mob, list: list} do
      [entry] = list.spells
      list = %{list | spells: [%{entry | cast_target: :friendly_injured, target_param1: 45}]}
      memory = Spells.set_list(Blackboard.new(), list, context(0))
      changed = %{mob | internal: %{mob.internal | blackboard: memory}}
      assert Spells.observation_radius(mob) == 0.0
      assert Spells.observation_radius(changed) == 45
    end
  end

  defp clear, do: %ScriptStep{command: :creature_spells}

  defp step(%CreatureSpellList{id: id} = list),
    do: %ScriptStep{command: :creature_spells, datalong: id, dataint: 100, creature_spell_lists: %{id => list}}

  defp context(now, roll \\ 1), do: Context.new(now, random: Random.fixed(0.5, roll))

  defp mob(_context) do
    spell = %Spell{id: 10, cast_time_ms: 0, range_yards: 0.0, mana_cost: 0, power_type: 0, effects: []}
    default = %CreatureSpell{spell_id: 10, cast_target: :self}

    switched = %CreatureSpell{
      spell_id: 20,
      cast_target: :self,
      delay_initial_min_ms: 2_000,
      delay_initial_max_ms: 3_000
    }

    mob = %Mob{
      object: %Object{guid: 1, entry: 4052},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [], flags: 0, stand_state: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        creature: %Creature{spells: [default]},
        spellbook: %{10 => spell, 20 => %{spell | id: 20}}
      }
    }

    %{mob: mob, list: %CreatureSpellList{id: 2, spells: [switched]}}
  end
end
