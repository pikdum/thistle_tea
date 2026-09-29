defmodule ThistleTea.Game.Core.AI.BT.Pet.TargetSelectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.AI.BT.Pet.TargetSelection
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef

  setup [:combat]

  describe "next/2" do
    test "prefers own attackers, then the owner's victim, then owner attackers", %{
      pet: pet,
      context: context,
      targets: [a, b, c]
    } do
      assert TargetSelection.next(pet, context) == a
      context = update_actor(context, a, alive?: false)
      assert TargetSelection.next(pet, context) == b
      context = update_actor(context, b, alive?: false)
      assert TargetSelection.next(pet, context) == c
      assert TargetSelection.next(pet, update_actor(context, c, alive?: false)) == nil
    end

    test "a selected target and stale combat observations do not count as attackers", %{
      pet: pet,
      context: context,
      targets: [a, b, c]
    } do
      context =
        context
        |> update_actor(a, in_combat: false)
        |> update_actor(b, combat_victim_guid: nil)
        |> update_actor(c, combat_victim_guid: nil, victim_guid: pet.internal.pet.owner_guid)
        |> update_actor(pet.internal.pet.owner_guid, combat_victim_guid: nil, victim_guid: b)

      assert TargetSelection.next(pet, context) == nil
    end

    test "owner targets require combat but own attackers do not", %{pet: pet, context: context, targets: [a, _, _]} do
      context = update_actor(context, pet.internal.pet.owner_guid, in_combat: false)
      assert TargetSelection.next(pet, context) == a
      assert TargetSelection.next(pet, update_actor(context, a, alive?: false)) == nil
    end

    test "Stay, passive, possession, and recall suppress follow-on attacks", %{pet: pet, context: context} do
      for control <- [
            %{pet.internal.pet | command_state: :stay},
            %{pet.internal.pet | reaction_state: :passive},
            %{pet.internal.pet | possessed?: true},
            %{pet.internal.pet | broken?: true}
          ] do
        blocked = %{pet | internal: %{pet.internal | pet: control}}
        assert TargetSelection.next(blocked, context) == nil
      end

      recalled = PetBT.command(pet, :follow, 0, context.now)
      assert TargetSelection.next(recalled, context) == nil
    end

    test "skips crowd control and PvP protection while finding the next legal target", %{
      pet: pet,
      context: context,
      targets: [a, b, c]
    } do
      context = context |> update_actor(a, breakable_crowd_control?: true) |> update_actor(b, unit_flags: 0x1000)
      assert TargetSelection.next(pet, context) == c
    end

    test "rejects absent owners and candidates in another world", %{pet: pet, context: context, targets: [a, _, _]} do
      owner = pet.internal.pet.owner_guid

      missing = %{
        context
        | perception: %{context.perception | entities: Map.delete(context.perception.entities, owner)}
      }

      assert TargetSelection.next(pet, missing) == nil
      context = update_actor(context, owner, in_combat: false)
      observation = context.perception.entities[a]
      observation = %{observation | position: {WorldRef.instance(999, 1), 10.0, 0.0, 0.0}}

      context = %{
        context
        | perception: %{context.perception | entities: Map.put(context.perception.entities, a, observation)}
      }

      assert TargetSelection.next(pet, context) == nil
    end

    test "NPC pets use threat order and never restart combat while their owner evades", %{
      pet: pet,
      context: context,
      targets: [a, b, c]
    } do
      owner = Guid.from_low_guid(:mob, 10, 50)
      owner_observation = %{context.perception.entities[1] | guid: owner}

      context = %{
        context
        | perception: %{context.perception | entities: Map.put(context.perception.entities, owner, owner_observation)}
      }

      pet = %{
        pet
        | internal: %{
            pet.internal
            | pet: %{pet.internal.pet | owner_guid: owner},
              threat: %{a => 10.0, b => 30.0, c => 30.0}
          }
      }

      assert TargetSelection.next(pet, context) == b
      assert TargetSelection.next(pet, update_actor(context, b, breakable_crowd_control?: true)) == c
      assert TargetSelection.next(pet, update_actor(context, owner, evading?: true)) == nil
    end
  end

  describe "victim_died/3" do
    test "kill feedback excludes its victim even before death metadata is published", %{
      pet: pet,
      context: context,
      targets: [a, b, _]
    } do
      pet = PetBT.command(pet, :attack, a, 900)
      continued = PetBT.victim_died(pet, a, context)
      assert continued.unit.target == b
      assert continued.internal.in_combat
      refute continued.internal.pet.attack_command?
      assert PetBT.victim_died(pet, b, context) == pet
    end
  end

  describe "tree/0" do
    test "a dead commanded victim yields to an attacker without losing combat or issuing another command", %{
      pet: pet,
      context: context,
      targets: [a, _, _]
    } do
      dead = Guid.from_low_guid(:mob, 17, 99)
      pet = PetBT.command(pet, :attack, dead, 900)
      pet = %{pet | internal: %{pet.internal | events: [], threat: Map.put(pet.internal.threat, a, 15.0)}}
      assert {:success, continued} = BT.tick(PetBT.tree(), pet, context)
      assert continued.unit.target == a
      assert continued.internal.in_combat
      assert continued.internal.threat[a] == 15.0
      refute continued.internal.pet.attack_command?
      assert continued.internal.blackboard.pet.returning == nil
      assert Enum.any?(continued.internal.events, &match?(%Effects.AttackStop{target_guid: ^dead}, &1))
      assert Enum.any?(continued.internal.events, &match?(%Effects.AttackerGained{target_guid: ^a}, &1))
    end

    test "an explicit command does not carry its override into a protected next target", %{
      pet: pet,
      context: context,
      targets: targets
    } do
      pet = PetBT.command(pet, :attack, Guid.from_low_guid(:mob, 17, 99), 900)
      context = Enum.reduce(targets, context, &update_actor(&2, &1, breakable_crowd_control?: true))
      assert {:success, returning} = BT.tick(PetBT.tree(), pet, context)
      assert returning.unit.target == 0
      assert returning.internal.in_combat
      refute returning.internal.pet.attack_command?
      assert returning.internal.blackboard.pet.returning == :combat
      assert returning.internal.threat == %{}
    end
  end

  defp combat(_context) do
    guid = Guid.from_low_guid(:pet, 1, 1)
    targets = Enum.map(2..4, &Guid.from_low_guid(:mob, 17, &1))
    [a, b, c] = targets
    world = WorldRef.open(999)

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10, flags: 0, combat_reach: 1.5, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, blackboard: %Blackboard{}, pet: %Pet{kind: :hunter, owner_guid: 1}}
    }

    observations = Map.new(targets, &{&1, enemy(&1, if(&1 == a, do: guid, else: 1), world)})

    source = %Observation{
      guid: guid,
      metadata: %{faction_template: %DBC.FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}}
    }

    owner = %Observation{
      guid: 1,
      position: {world, 0.0, 0.0, 0.0},
      metadata: %{in_combat: true, combat_victim_guid: b, combat_targets: [b, c]}
    }

    observations = observations |> Map.put(guid, source) |> Map.put(1, owner)
    perception = Perception.new(1_000, {world, 0.0, 0.0, 0.0}, observations, %{})
    %{pet: pet, context: Context.new(1_000, perception: perception), targets: targets}
  end

  defp enemy(guid, victim, world) do
    %Observation{
      guid: guid,
      distance: 10.0,
      position: {world, 10.0, 0.0, 0.0},
      metadata: %{
        alive?: true,
        level: 10,
        in_combat: true,
        combat_victim_guid: victim,
        faction_template: %DBC.FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
      }
    }
  end

  defp update_actor(context, guid, values) do
    actor = context.perception.entities[guid]
    actor = %{actor | metadata: Map.merge(actor.metadata, Map.new(values))}
    %{context | perception: %{context.perception | entities: Map.put(context.perception.entities, guid, actor)}}
  end
end
