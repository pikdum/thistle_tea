defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet.TargetingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Acquisition
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet.Targeting
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  setup [:pet]

  describe "automatic_allowed?/3" do
    test "Stay permits contact targets but does not acquire distant enemies", %{pet: pet, target: target} do
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | command_state: :stay}}}
      near = context(pet, target, 5.0)
      far = context(pet, target, 5.01)
      assert Targeting.automatic_allowed?(pet, target, near)
      refute Targeting.automatic_allowed?(pet, target, far)
      assert Acquisition.nearest(pet, near) == target
      assert Acquisition.nearest(pet, far) == nil
    end

    test "excludes breakable control from pet acquisition", %{pet: pet, target: target} do
      protected = context(pet, target, 10.0, breakable_crowd_control?: true)
      refute Targeting.automatic_allowed?(pet, target, protected)
      assert Acquisition.nearest(pet, protected) == nil

      clear = context(pet, target, 10.0, breakable_crowd_control?: false)
      assert Targeting.automatic_allowed?(pet, target, clear)
      assert Acquisition.nearest(pet, clear) == target
    end

    test "aggressive guardians retain their uncontrolled attack behavior", %{pet: pet, target: target} do
      guardian = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | kind: :guardian}}}
      protected = context(guardian, target, 10.0, breakable_crowd_control?: true)
      assert Acquisition.nearest(guardian, protected) == target
      ordinary = %{pet | internal: %{pet.internal | pet: nil}}
      assert Acquisition.nearest(ordinary, protected) == target
    end

    test "unflagged player pets do not automatically engage flagged targets", %{pet: pet, target: target} do
      flagged_target = context(pet, target, 5.0, unit_flags: 0x1000)
      refute Targeting.automatic_allowed?(pet, target, flagged_target)
      flagged_pet = %{pet | unit: %{pet.unit | flags: 0x1000}}
      assert Targeting.automatic_allowed?(flagged_pet, target, flagged_target)
      assert Targeting.automatic_allowed?(pet, target, context(pet, target, 5.0))

      creature_pet = %{
        pet
        | internal: %{pet.internal | pet: %{pet.internal.pet | owner_guid: Guid.from_low_guid(:mob, 1, 90)}}
      }

      assert Targeting.automatic_allowed?(creature_pet, target, flagged_target)
    end

    test "passive, broken, and possessed pets do not choose automatic attacks", %{pet: pet, target: target} do
      context = context(pet, target, 2.0)

      for control <- [
            %{pet.internal.pet | reaction_state: :passive},
            %{pet.internal.pet | broken?: true},
            %{pet.internal.pet | possessed?: true}
          ] do
        blocked = %{pet | internal: %{pet.internal | pet: control}}
        refute Targeting.automatic_allowed?(blocked, target, context)
      end
    end
  end

  describe "autocast_allowed?/4" do
    test "explicit Attack overrides control, stance, and PvP protection for that target", %{pet: pet, target: target} do
      spell = %Spell{id: 1, effects: [%Spell.Effect{type: :school_damage, implicit_target_a: :target_enemy}]}
      context = context(pet, target, 15.0, breakable_crowd_control?: true, unit_flags: 0x1000)
      refute Targeting.autocast_allowed?(pet, spell, target, context)

      commanded = %{
        pet
        | unit: %{pet.unit | target: target},
          internal: %{pet.internal | pet: %{pet.internal.pet | command_state: :attack, reaction_state: :passive}}
      }

      assert Targeting.autocast_allowed?(commanded, spell, target, context)
      refute Targeting.autocast_allowed?(commanded, spell, target + 1, context)
      assert Targeting.autocast_allowed?(pet, %Spell{id: 2}, target, context)
    end
  end

  describe "owner_defense?/3" do
    test "keeps a living victim and permits replacement after its death", %{pet: pet, target: target} do
      current = target + 1
      context = context(pet, target, 10.0)
      observation = %{context.perception.entities[target] | guid: current}
      perception = %{context.perception | entities: Map.put(context.perception.entities, current, observation)}
      context = %{context | perception: perception}
      pet = %{pet | unit: %{pet.unit | target: current}, internal: %{pet.internal | in_combat: true}}
      refute Targeting.owner_defense?(pet, target, context)

      dead = %{observation | metadata: %{observation.metadata | alive?: false}}
      perception = %{perception | entities: Map.put(perception.entities, current, dead)}
      assert Targeting.owner_defense?(pet, target, %{context | perception: perception})
    end

    test "rejects distant Stay reactions and crowd-controlled attackers", %{pet: pet, target: target} do
      assert Targeting.owner_defense?(pet, target, context(pet, target, 10.0))
      refute Targeting.owner_defense?(pet, target, context(pet, target, 10.0, breakable_crowd_control?: true))
      pet = %{pet | internal: %{pet.internal | pet: %{pet.internal.pet | command_state: :stay}}}
      refute Targeting.owner_defense?(pet, target, context(pet, target, 10.0))
      assert Targeting.owner_defense?(pet, target, context(pet, target, 2.0))
    end
  end

  defp pet(_context) do
    pet = %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 1, 1)},
      unit: %Unit{health: 100, level: 10, flags: 0, combat_reach: 1.5, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(999),
        in_combat: false,
        pet: %Internal.Pet{kind: :hunter, owner_guid: 1, reaction_state: :aggressive}
      }
    }

    %{pet: pet, target: Guid.from_low_guid(:mob, 17, 2)}
  end

  defp context(pet, target, distance, extra \\ []) do
    world = pet.internal.world

    source = %Observation{
      guid: pet.object.guid,
      metadata: %{faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}}
    }

    target = %Observation{
      guid: target,
      distance: distance,
      position: {world, distance, 0.0, 0.0},
      metadata:
        Map.merge(
          %{
            alive?: true,
            level: 10,
            faction_template: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
          },
          Map.new(extra)
        )
    }

    perception =
      Perception.new(1_000, {world, 0.0, 0.0, 0.0}, Map.new([source, target], &{&1.guid, &1}), %{
        mobs: [{target.guid, distance}]
      })

    Context.new(1_000, perception: perception)
  end
end
