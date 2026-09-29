defmodule ThistleTea.Game.Core.AI.BT.AcquisitionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Acquisition
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Combat.Aggro
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Creature.CreatureReaction
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef

  @now 10_000

  describe "nearest/2" do
    setup [:build_pet]

    test "acquires lower-level enemies beyond twenty yards", %{entity: entity} do
      target = target(1, 25.0, level: 1)
      assert Acquisition.nearest(entity, context(entity, [target])) == target.guid
      target = %{target | metadata: %{target.metadata | level: 10}}
      assert Acquisition.nearest(entity, context(entity, [target])) == nil
    end

    test "uses the player's level for an owned or charmed target", %{entity: entity} do
      target = %{target(1, 10.0, level: 1) | controller_level: 60}
      assert Acquisition.nearest(entity, context(entity, [target])) == nil
      assert Acquisition.nearest(entity, context(entity, [%{target | controller_level: nil}])) == target.guid
    end

    test "detect range auras preserve minimum distance and disabled detection", %{entity: entity} do
      entity = with_aura(entity, :mod_detect_range, -100)
      target = target(1, 5.0)
      assert Aggro.search_radius(entity) == 5.0
      assert Acquisition.nearest(entity, context(entity, [target])) == target.guid
      assert Acquisition.nearest(entity, context(entity, [target(1, 5.1)])) == nil

      entity = %{entity | internal: %{entity.internal | creature: %Internal.Creature{detection_range: 0.0}}}
      assert Aggro.search_radius(entity) == 0.0
      assert Acquisition.nearest(entity, context(entity, [target(1, 0.0)])) == nil
    end

    test "detect range bonuses expand the search envelope", %{entity: entity} do
      entity = with_aura(entity, :mod_detect_range, 30)
      target = target(1, 50.0)
      assert Acquisition.nearest(entity, context(entity, [target])) == target.guid
    end

    test "passes over unseen targets for the nearest detectable enemy", %{entity: entity} do
      hidden = target(1, 5.0, stealthed?: true, stealth_skill: 50)
      invisible = target(2, 6.0, invisibility: %{0 => 100})
      obstructed = %{target(3, 7.0) | line_of_sight?: false}
      visible = target(4, 8.0)

      assert Acquisition.nearest(entity, context(entity, [hidden, invisible, obstructed, visible])) == visible.guid

      marked = %{hidden | metadata: Map.put(hidden.metadata, :stalked_by, [entity.object.guid])}
      assert Acquisition.nearest(entity, context(entity, [marked, visible])) == marked.guid
    end

    test "does not initiate while stunned or pacified", %{entity: entity} do
      for type <- [:mod_stun, :mod_pacify] do
        blocked = with_aura(entity, type, 0)
        assert Acquisition.nearest(blocked, context(blocked, [target(1, 2.0)])) == nil
      end
    end

    test "ignores dead, untargetable, and friendly units", %{entity: entity} do
      dead = target(1, 1.0, alive?: false)
      untargetable = target(2, 2.0, unit_flags: 0x02000000)
      friendly = target(3, 3.0, faction_template: source_faction())
      assert Acquisition.nearest(entity, context(entity, [dead, untargetable, friendly])) == nil
    end

    test "protects civilians from pets and guardians without changing ordinary creature hostility", %{entity: entity} do
      civilian = target(1, 5.0, civilian?: true)

      for kind <- [:hunter, :summon, :guardian] do
        pet = %{entity | internal: %{entity.internal | pet: %{entity.internal.pet | kind: kind}}}
        assert Acquisition.nearest(pet, context(pet, [civilian])) == nil
      end

      ordinary = %{entity | internal: %{entity.internal | pet: nil}}
      assert Acquisition.nearest(ordinary, context(ordinary, [civilian])) == civilian.guid
    end

    test "limits ground acquisition to three yards between bounding surfaces", %{entity: entity} do
      reachable = %{target(1, 5.0) | position: {world(), 4.0, 0.0, 4.0}}
      unreachable = %{reachable | position: {world(), 4.0, 0.0, 4.01}}
      assert Acquisition.nearest(entity, context(entity, [reachable])) == reachable.guid
      assert Acquisition.nearest(entity, context(entity, [unreachable])) == nil

      flyer = %{entity | internal: %{entity.internal | creature: %Internal.Creature{inhabit_type: 4}}}
      assert Acquisition.nearest(flyer, context(flyer, [unreachable])) == unreachable.guid

      hunter = %{flyer | internal: %{flyer.internal | pet: %{flyer.internal.pet | kind: :hunter}}}
      assert Acquisition.nearest(hunter, context(hunter, [unreachable])) == nil
    end

    test "requires an accessible habitat", %{entity: entity} do
      swimmer = %{entity | internal: %{entity.internal | creature: %Internal.Creature{inhabit_type: 2}}}
      land = %{target(1, 4.0) | swimmable?: false}
      water = %{target(2, 5.0) | swimmable?: true}
      assert Acquisition.nearest(swimmer, context(swimmer, [land, water])) == water.guid

      walker = %{entity | internal: %{entity.internal | creature: %Internal.Creature{inhabit_type: 1}}}
      assert Acquisition.nearest(walker, context(walker, [water])) == nil
    end

    test "breaks equal-distance ties by guid", %{entity: entity} do
      first = target(1, 5.0)
      second = target(2, 5.0)
      assert Acquisition.nearest(entity, context(entity, [second, first])) == first.guid
    end

    test "only aggressive creatures acquire nearby enemies", %{entity: entity} do
      enemy = target(1, 5.0)

      for pet <- [entity.internal.pet, nil], mode <- [:passive, :defensive, :aggressive] do
        creature = %{entity | internal: %{entity.internal | pet: pet}} |> CreatureReaction.set(mode)
        expected = if mode == :aggressive, do: enemy.guid
        assert Acquisition.nearest(creature, context(creature, [enemy])) == expected
      end
    end
  end

  defp build_pet(_context) do
    entity = %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 1, 1)},
      unit: %Unit{health: 100, level: 10, bounding_radius: 0.5, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: world(),
        creature: %Internal.Creature{detection_range: 20.0, inhabit_type: 1},
        pet: %Internal.Pet{kind: :guardian, reaction_state: :aggressive}
      }
    }

    %{entity: entity}
  end

  defp target(low_guid, distance, metadata \\ []) do
    %Observation{
      guid: Guid.from_low_guid(:mob, 17, low_guid),
      position: {world(), distance, 0.0, 0.0},
      distance: distance,
      metadata:
        Map.merge(
          %{alive?: true, level: 10, bounding_radius: 0.5, faction_template: enemy_faction()},
          Map.new(metadata)
        )
    }
  end

  defp context(entity, targets) do
    source = %Observation{guid: entity.object.guid, metadata: %{faction_template: source_faction()}}
    observations = Map.new([source | targets], &{&1.guid, &1})
    nearby = %{mobs: Enum.map(targets, &{&1.guid, &1.distance})}
    perception = Perception.new(@now, {world(), 0.0, 0.0, 0.0}, observations, nearby)
    Context.new(@now, perception: perception)
  end

  defp with_aura(entity, type, amount) do
    holder = %Holder{auras: [%Aura{type: type, amount: amount}]}
    %{entity | unit: %{entity.unit | auras: [holder]}}
  end

  defp source_faction, do: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
  defp enemy_faction, do: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
  defp world, do: WorldRef.open(999)
end
