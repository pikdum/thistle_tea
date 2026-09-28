defmodule ThistleTea.Game.Entity.Logic.CreatureReactionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Assistance
  alias ThistleTea.Game.Entity.Logic.CreatureReaction
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Script, as: ScriptLoader

  setup [:mob]

  describe "mode/1" do
    test "uses template defaults and lets scripts override them", %{mob: mob} do
      for {creature, expected} <- [
            {%Creature{}, :aggressive},
            {%Creature{extra_flags: 0x2}, :defensive},
            {%Creature{extra_flags: 0x80}, :passive},
            {%Creature{extra_flags: 0x20000}, :passive},
            {%Creature{static_flags: 0x02000000}, :passive},
            {%Creature{extra_flags: 0x20002}, :passive}
          ] do
        entity = %{mob | internal: %{mob.internal | creature: creature}}
        assert CreatureReaction.mode(entity) == expected
        assert CreatureReaction.mode(CreatureReaction.set(entity, :aggressive)) == :aggressive
      end
    end

    test "uses the pet's reaction instead of its creature template", %{mob: mob} do
      mob = %{mob | internal: %{mob.internal | pet: %Pet{reaction_state: :defensive}}}
      assert CreatureReaction.mode(mob) == :defensive
      refute Mob.proximity_aggro?(mob)
    end
  end

  describe "set/2" do
    test "passive creatures refuse combat entry, damage retaliation, and assistance", %{mob: mob} do
      passive = CreatureReaction.set(mob, :passive)
      assert %Engagement.Result{entity: ^passive, reason: :passive} = Engagement.enter(passive, 1, 100)
      assert Engagement.on_damage(passive, 1, 100) == passive
      refute Assistance.available?(passive)

      for mode <- [:defensive, :aggressive] do
        active = CreatureReaction.set(mob, mode)
        assert Assistance.available?(active)
        attacked = Engagement.on_damage(active, 1, 100)
        assert attacked.unit.target == 1
        assert attacked.internal.in_combat
      end
    end

    test "retains an existing fight and the mode across combat exit and respawn", %{mob: mob} do
      %{entity: fighting} = Engagement.enter(mob, 1, 100, selection: :target)
      passive = CreatureReaction.set(fighting, :passive)
      assert passive.unit.target == 1
      assert passive.internal.threat == fighting.internal.threat
      assert passive.internal.in_combat
      %{entity: idle} = Engagement.leave(passive, :evade)
      assert CreatureReaction.mode(idle) == :passive
      assert CreatureReaction.mode(Mob.respawn(idle)) == :passive
    end

    test "updates the pet owner once and preserves explicit attack commands", %{mob: mob} do
      pet = %{mob | internal: %{mob.internal | pet: %Pet{owner_guid: 1}}}
      passive = CreatureReaction.set(pet, :passive)
      assert [%Effects.PetReactionChanged{target_guid: 1, reaction_state: :passive}] = passive.internal.events
      assert CreatureReaction.set(passive, :passive) == passive
      commanded = PetBT.command(passive, :attack, 2, 100)
      assert commanded.unit.target == 2
      assert commanded.internal.pet.attack_command?
      stopped = PetBT.reaction(commanded, :passive)
      assert stopped.unit.target in [nil, 0]
      refute stopped.internal.pet.attack_command?
    end
  end

  describe "Script.execute_steps/5" do
    test "accepts all reaction modes and marks metadata for publication", %{mob: mob} do
      for {value, mode} <- [{0, :passive}, {1, :defensive}, {2, :aggressive}] do
        step = %ScriptStep{command: :set_react_state, datalong: value}
        {updated, _} = Script.execute_steps(mob, Blackboard.new(), [step], 0, Context.new(100))
        assert CreatureReaction.mode(updated) == mode
        assert updated.internal.broadcast_update?
      end
    end

    test "invalid modes and non-creature sources honor abort", %{mob: mob} do
      character = %Character{object: %Object{guid: 1}, internal: %Internal{}}

      for {entity, value} <- [{mob, 3}, {character, 0}], abort? <- [true, false] do
        step = %ScriptStep{command: :set_react_state, datalong: value, abort_on_failure?: abort?}
        next = %ScriptStep{command: :set_phase, datalong: 7}
        {updated, memory} = Script.execute_steps(entity, Blackboard.new(), [step, next], 0, Context.new(100))
        assert updated == entity
        assert memory.event_ai.phase == if(abort?, do: 0, else: 7)
      end
    end

    @tag :vmangos_db
    test "loads passive Thornling and defensive Timbermaw Ancestor scripts", %{mob: mob} do
      scripts = ScriptLoader.load_by_ids(Mangos.CreatureAiScript, [1_436_201, 1_572_002])

      for {id, value, mode} <- [{1_436_201, 0, :passive}, {1_572_002, 1, :defensive}] do
        step = Enum.find(scripts[id], &(&1.command == :set_react_state))
        assert step.datalong == value
        {updated, _} = Script.execute_steps(mob, Blackboard.new(), [step], 0, Context.new(100))
        assert CreatureReaction.mode(updated) == mode
      end
    end
  end

  defp mob(_context) do
    mob = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
      unit: %Unit{health: 100, max_health: 100, flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{creature: %Creature{}, blackboard: Blackboard.new(), in_combat: false}
    }

    %{mob: mob}
  end
end
