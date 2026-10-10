defmodule ThistleTea.Game.Core.AI.BT.ScriptedMeleeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Combat
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:combatants]

  describe "melee_attack_with_context/3" do
    test "replaces ready swings at the current attack speed", %{mob: mob} do
      {mob, blackboard} = configure(mob, :set_melee_spell, 19_319)
      {mob, blackboard} = swing(mob, blackboard, 1_000)
      assert replacement_spells(mob) == [19_319]
      refute Enum.any?(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert Blackboard.delay_until(blackboard, :next_attack_at, 1_000) == 2_000

      {mob, blackboard} = swing(mob, blackboard, 2_999)
      assert replacement_spells(mob) == []
      mob = %{mob | unit: %{mob.unit | base_attack_time: 1_200}}
      {mob, blackboard} = swing(mob, blackboard, 3_000)
      assert replacement_spells(mob) == [19_319]
      assert Blackboard.delay_until(blackboard, :next_attack_at, 3_000) == 1_200
    end

    test "replacement spells retain range, world, life and control checks", %{mob: mob} do
      {mob, blackboard} = configure(mob, :set_melee_spell, 19_319)

      for {auras, health, position, alive?} <- [
            {[], 100, {mob.internal.world, 20.0, 0.0, 0.0}, true},
            {[], 100, {WorldRef.instance(409, Unique.integer()), 1.0, 0.0, 0.0}, true},
            {[], 100, {mob.internal.world, 1.0, 0.0, 0.0}, false},
            {[], 0, {mob.internal.world, 1.0, 0.0, 0.0}, true},
            {[%Holder{auras: [%Aura{type: :mod_pacify}]}], 100, {mob.internal.world, 1.0, 0.0, 0.0}, true},
            {[%Holder{auras: [%Aura{type: :mod_stun}]}], 100, {mob.internal.world, 1.0, 0.0, 0.0}, true}
          ] do
        state = %{mob | unit: %{mob.unit | auras: auras, health: health}}
        context = context(state, 1_000, position, alive?)
        {:success, state, memory} = Combat.melee_attack_with_context(state, blackboard, context)
        assert replacement_spells(state) == []
        refute Enum.any?(state.internal.events, &is_struct(&1, Effects.DeliverAttack))
        assert Blackboard.delay_until(memory, :next_attack_at, 1_000) == 100
      end
    end

    test "controlled creatures use ordinary swings", %{mob: mob} do
      {mob, blackboard} = configure(mob, :set_melee_spell, 19_319)
      mob = %{mob | internal: %{mob.internal | pet: %Pet{kind: :charmed, owner_guid: Unique.integer()}}}
      {mob, _blackboard} = swing(mob, blackboard, 1_000)
      assert replacement_spells(mob) == []
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
    end

    test "clearing the override restores ordinary swings", %{mob: mob} do
      {mob, _blackboard} = configure(mob, :set_melee_spell, 19_319)
      {mob, blackboard} = configure(mob, :set_melee_spell, 0)
      {mob, _blackboard} = swing(mob, blackboard, 1_000)
      assert mob.internal.creature.melee_spell_id == nil
      assert replacement_spells(mob) == []
      assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.DeliverAttack))
    end
  end

  describe "execute_steps/5" do
    test "suppresses automatic assistance before combat entry", %{mob: mob} do
      assert Enum.any?(
               MobBT.maybe_enqueue_call_assistance(mob, mob.unit.target).internal.events,
               &is_struct(&1, Effects.CallAssistance)
             )

      {mob, _blackboard} = configure(mob, :set_call_for_help_range, 0)
      assert mob.internal.creature.call_for_help_range == 0
      assert MobBT.maybe_enqueue_call_assistance(mob, mob.unit.target).internal.events == []
    end
  end

  defp combatants(_context) do
    target = Unique.integer()

    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, Unique.integer(), Unique.integer())},
      unit: %Unit{
        health: 100,
        level: 60,
        flags: 0,
        auras: [],
        target: target,
        base_attack_time: 2_000,
        min_damage: 10.0,
        max_damage: 10.0
      },
      internal: %Internal{
        world: WorldRef.instance(409, Unique.integer()),
        creature: %Creature{call_for_help_range: 5.0},
        in_combat: true
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{mob: mob}
  end

  defp configure(mob, command, value) do
    step = %ScriptStep{command: command, datalong: value}
    Script.execute_steps(mob, Blackboard.new(), [step], nil, context(mob, 0))
  end

  defp swing(mob, blackboard, now) do
    mob = %{mob | internal: %{mob.internal | events: []}}
    {:success, mob, blackboard} = Combat.melee_attack_with_context(mob, blackboard, context(mob, now))
    {mob, blackboard}
  end

  defp context(mob, now, position \\ nil, alive? \\ true) do
    position = position || {mob.internal.world, 1.0, 0.0, 0.0}
    observation = %Observation{guid: mob.unit.target, position: position, metadata: %{alive?: alive?}}
    perception = Perception.new(now, nil, %{mob.unit.target => observation}, %{})
    Context.new(now, perception: perception)
  end

  defp replacement_spells(mob) do
    for %Effects.TriggerSpell{spell_id: id} <- mob.internal.events, do: id
  end
end
