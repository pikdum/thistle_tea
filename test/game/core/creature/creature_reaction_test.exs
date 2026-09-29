defmodule ThistleTea.Game.Core.Creature.CreatureReactionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.BehaviorRunner
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Combat.Assistance
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Combat.Threat
  alias ThistleTea.Game.Core.Creature.CreatureReaction
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Power.Regen
  alias ThistleTea.Game.World.Combat.ThreatSelection
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

      assert %Engagement.Result{entity: ^passive, reason: :passive} =
               Engagement.enter(passive, 1, 100, ThreatSelection.opts(passive))

      attacked = Engagement.on_damage(passive, 1, 100)
      assert attacked.internal.in_combat
      assert attacked.internal.threat == %{1 => 0.0}
      assert attacked.unit.target in [nil, 0]
      assert MobBT.maybe_enqueue_call_assistance(attacked, 1) == attacked
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
      %{entity: idle} = Engagement.leave(passive, :evade, 1_000)
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
      stopped = PetBT.reaction(commanded, :passive, 200)
      assert stopped.unit.target in [nil, 0]
      refute stopped.internal.pet.attack_command?
    end

    test "preserves the current victim but refuses replacements while passive", %{mob: mob} do
      %{entity: fighting} = Engagement.enter(mob, 1, 100, selection: :target)
      passive = fighting |> CreatureReaction.set(:passive) |> Threat.add(2, 100)

      %{entity: unchanged, decision: :keep} =
        Engagement.select(passive, valid?: fn _ -> true end, in_melee?: fn _ -> false end)

      assert unchanged.unit.target == 1

      %{entity: waiting, decision: :keep} = Engagement.select(passive, valid?: &(&1 == 2), in_melee?: fn _ -> false end)
      assert waiting.unit.target == 0
      assert waiting.internal.threat == %{2 => 100.0}
      assert waiting.internal.in_combat
      assert Enum.any?(waiting.internal.events, &match?(%Effects.AttackStop{target_guid: 1}, &1))
      refute Enum.any?(waiting.internal.events, &match?(%Effects.AttackerGained{target_guid: 2}, &1))
    end
  end

  describe "BehaviorRunner.tick/3" do
    test "passive damage retains combat without attacking or regenerating", %{mob: mob} do
      mob = %{mob | unit: %{mob.unit | health: 50}}
      attacked = mob |> CreatureReaction.set(:passive) |> Engagement.on_damage(1, 100)
      assert Regen.tick(attacked, 1_000).unit.health == 50
      context = combat_context(attacked)

      assert {{:running, 1_000, :passive_combat}, waiting} =
               BehaviorRunner.tick(MobBT.tree(), attacked, context)

      assert waiting.unit.target in [nil, 0]
      assert waiting.unit.health == 50
      assert waiting.internal.in_combat
      assert waiting.internal.threat == %{1 => 0.0}
      refute Enum.any?(waiting.internal.events, &is_struct(&1, Effects.AttackStart))

      %{entity: defensive, decision: {:switch, 1}} =
        waiting
        |> CreatureReaction.set(:defensive)
        |> Engagement.select(valid?: fn _ -> true end, in_melee?: fn _ -> false end)

      assert defensive.unit.target == 1

      {_status, reset} = BehaviorRunner.tick(MobBT.tree(), waiting, Context.new(2_000))
      refute reset.internal.in_combat
      assert reset.internal.threat == %{}
      assert Enum.any?(reset.internal.events, &match?(%Effects.ThreatRefLost{target_guid: 1}, &1))
      assert CreatureReaction.mode(reset) == :passive
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
      internal: %Internal{
        creature: %Creature{regenerate_stats: 3, call_for_help_range: 10.0},
        spawn: %Spawn{position: {0.0, 0.0, 0.0}},
        blackboard: Blackboard.new(),
        in_combat: false
      }
    }

    %{mob: mob}
  end

  defp combat_context(mob) do
    source = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
    enemy = %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}

    observations = %{
      mob.object.guid => %Observation{guid: mob.object.guid, metadata: %{faction_template: source}},
      1 => %Observation{
        guid: 1,
        metadata: %{alive?: true, faction_template: enemy},
        position: {mob.internal.world, 2.0, 0.0, 0.0},
        distance: 2.0
      }
    }

    perception = Perception.new(1_000, {mob.internal.world, 0.0, 0.0, 0.0}, observations, %{})
    Context.new(1_000, perception: perception)
  end
end
