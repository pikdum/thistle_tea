defmodule ThistleTea.Game.Entity.Logic.Engagement.PetCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Entity.Logic.Threat
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  @combat_flags 0x00080800

  setup [:entities]

  describe "maintain/2" do
    test "incoming threat prevents health regeneration without a selected victim", %{pet: pet, enemy: enemy} do
      pet = Engagement.gain_threat_ref(pet, enemy, 7, 0)
      pet = PetBT.command(pet, :follow, 0, 1_000)
      context = context(pet, enemy, 20_000)
      tree = BT.action(fn entity, blackboard -> {:failure, entity, blackboard} end)
      assert {:failure, waiting} = BehaviorRunner.tick(tree, pet, context)
      assert waiting.unit.health == 50
      assert waiting.unit.target == 0
      assert waiting.internal.in_combat
      assert Bitwise.band(waiting.unit.flags, @combat_flags) == @combat_flags
      assert waiting.internal.blackboard.pet.returning == :command

      released = Engagement.lose_threat_ref(waiting, enemy, 7)
      assert {:failure, resting} = BehaviorRunner.tick(tree, released, %{context | now: 30_000})
      refute resting.internal.in_combat
      assert resting.unit.health > 50
      assert Bitwise.band(resting.unit.flags, @combat_flags) == 0
    end

    test "prunes dead, despawned, evading, inactive, moved and reincarnated enemies", %{pet: pet, enemy: enemy} do
      pet = Engagement.gain_threat_ref(pet, enemy, 7, 0)
      context = context(pet, enemy, 20_000)
      observation = context.perception.entities[enemy]

      stale = [
        %{observation | metadata: %{observation.metadata | alive?: false}},
        %{observation | metadata: %{observation.metadata | incarnation_id: 8}},
        %{observation | metadata: Map.put(observation.metadata, :evading?, true)},
        %{observation | metadata: Map.put(observation.metadata, :in_combat, false)},
        %{observation | position: {WorldRef.open(2), 1.0, 0.0, 0.0}},
        %{observation | position: nil},
        %{observation | metadata: nil}
      ]

      for observed <- stale do
        perception = %{context.perception | entities: %{enemy => observed}}
        released = Engagement.maintain(pet, %{context | perception: perception})
        refute released.internal.in_combat
        assert released.internal.threat_refs == MapSet.new()
      end

      refute Engagement.maintain(pet, Context.new(20_000)).internal.in_combat
    end

    test "retains PvP contact across commands until the drop window expires", %{pet: pet} do
      pet = Engagement.contact(pet, 20, 1_000)
      assert pet.unit.target == nil

      for command <- [:stay, :follow] do
        commanded = pet |> PetBT.command(command, 0, 1_001) |> PetBT.reaction(:passive)
        assert commanded.unit.target == 0
        assert Engagement.maintain(commanded, Context.new(5_999)).internal.in_combat
        refute Engagement.maintain(commanded, Context.new(6_000)).internal.in_combat
      end
    end

    test "ending combat releases the pet's outgoing threat references", %{pet: pet, enemy: enemy} do
      pet = pet |> Engagement.contact(enemy, 1_000) |> Threat.add(enemy, 20)
      resting = Engagement.maintain(pet, Context.new(6_000))
      refute resting.internal.in_combat
      assert resting.internal.threat == %{}
      assert Enum.any?(resting.internal.events, &match?(%Effects.ThreatRefLost{target_guid: ^enemy}, &1))
      refute PetBT.command(resting, :follow, 0, 6_001).internal.in_combat
    end
  end

  describe "gain_threat_ref/4" do
    test "duplicate gains and stale losses preserve the current incarnation", %{pet: pet, enemy: enemy} do
      pet = pet |> Engagement.gain_threat_ref(enemy, 7, 0) |> Engagement.gain_threat_ref(enemy, 7, 0)
      assert pet.internal.threat_refs == MapSet.new([{enemy, 7}])
      assert Engagement.lose_threat_ref(pet, enemy, 6) == pet
      assert Engagement.lose_threat_ref(pet, enemy, 7).internal.threat_refs == MapSet.new()
    end
  end

  describe "receive/4" do
    test "outgoing melee refreshes contact without restarting a recalled attack", %{pet: pet} do
      pet = pet |> PetBT.command(:attack, 20, 1_000) |> PetBT.command(:follow, 0, 8_000)

      for outcome <- [:normal, :miss, :dodge, :parry, :immune] do
        updated = AttackFeedback.receive(pet, %{victim_guid: 20, outcome: outcome, damage: 0}, nil, 9_000)
        assert updated.unit.target == 0
        assert updated.internal.blackboard.pet.returning == :command
        assert Engagement.maintain(updated, Context.new(13_999)).internal.in_combat
        refute Engagement.maintain(updated, Context.new(14_000)).internal.in_combat
      end

      evaded = AttackFeedback.receive(pet, %{victim_guid: 20, outcome: :evade, damage: 0}, nil, 9_000)
      assert evaded.internal.last_hostile_time == pet.internal.last_hostile_time
    end
  end

  describe "die/1" do
    test "death clears references and rejects delayed combat messages", %{pet: pet, enemy: enemy} do
      pet = pet |> Engagement.gain_threat_ref(enemy, 7, 0) |> Engagement.contact(enemy, 1_000)
      dead = Engagement.die(%{pet | unit: %{pet.unit | health: 0}}).entity
      assert dead.internal.threat_refs == MapSet.new()
      assert dead.internal.last_hostile_time == nil
      assert Engagement.gain_threat_ref(dead, enemy, 7, 0) == dead
      assert Engagement.contact(dead, enemy, 2_000) == dead
      refute dead.internal.in_combat
      assert Bitwise.band(dead.unit.flags, @combat_flags) == 0
    end
  end

  defp entities(_context) do
    pet = %Mob{
      object: %Object{guid: Guid.runtime(:pet, 1)},
      unit: %Unit{health: 50, max_health: 100, flags: 0, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{pet: %Pet{kind: :hunter, owner_guid: 1}, world: WorldRef.open(0)}
    }

    %{pet: pet, enemy: Guid.runtime(:mob, 2)}
  end

  defp context(pet, enemy, now) do
    observation = %Observation{
      guid: enemy,
      position: {pet.internal.world, 30.0, 0.0, 0.0},
      metadata: %{alive?: true, incarnation_id: 7, in_combat: true}
    }

    Context.new(now, perception: Perception.new(now, nil, %{enemy => observation}, %{}))
  end
end
