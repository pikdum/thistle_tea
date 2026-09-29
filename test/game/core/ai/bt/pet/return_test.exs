defmodule ThistleTea.Game.Core.AI.BT.Pet.ReturnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Core.AI.BT.Pet.Targeting
  alias ThistleTea.Game.Core.AI.NavigationIntent
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Combat.ThreatSelection
  alias ThistleTea.Game.World.Entity.NavigationResolver

  setup [:pet]

  describe "command/4" do
    test "Attack preserves Stay and its interpolated anchor", %{pet: pet, target: target} do
      moving = Movement.move_along_path(pet, [{10.0, 2.0, 0.0}], [velocity: 10.0], 1_000)
      stayed = PetBT.command(moving, :stay, 0, 1_500)
      assert {x, 2.0, +0.0} = stayed.internal.pet.stay_position
      assert_in_delta x, 5.0, 0.01
      assert stayed.movement_block.spline_nodes == []
      attacked = PetBT.command(stayed, :attack, target, 1_500)
      assert attacked.internal.pet.command_state == :stay
      assert attacked.internal.pet.attack_command?
      assert attacked.internal.pet.stay_position == stayed.internal.pet.stay_position
    end

    test "an explicit Attack interrupts a Follow recall", %{pet: pet, target: target} do
      recalled = PetBT.command(pet, :follow, 0, 1_000)
      assert recalled.internal.blackboard.pet.returning == :command
      attacked = PetBT.command(recalled, :attack, target, 1_001)
      assert attacked.internal.blackboard.pet.returning == nil
      assert attacked.internal.pet.attack_command?
      assert attacked.unit.target == target
      assert attacked.internal.in_combat
    end

    test "Stay stops travel without discarding the current victim", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :attack, target, 1_000)
      pet = NavigationIntent.enqueue(pet, {30.0, 2.0, 0.0}, [])
      stayed = PetBT.command(pet, :stay, 0, 1_001)
      assert stayed.unit.target == target
      assert stayed.internal.in_combat
      refute stayed.internal.pet.attack_command?
      assert stayed.internal.navigation_intents == []
    end
  end

  describe "tree/0" do
    test "a newly commanded spell advances before return movement", %{pet: pet, target: target} do
      pet = %{pet | movement_block: %{pet.movement_block | position: {20.0, 2.0, 0.0, 0.0}}}
      spell = %Spell{id: 10, cast_time_ms: 1_000, mana_cost: 0, effects: []}
      pet = pet |> PetBT.command(:follow, 0, 1_000) |> Casting.start(spell, Target.none(), 1_000)
      context = context(pet, target)
      assert {{:running, 1_000}, preparing} = BT.tick(PetBT.tree(), pet, context)
      assert preparing.internal.navigation_intents == []
      assert preparing.internal.blackboard.pet.returning == :command
      assert {:success, finished} = BT.tick(PetBT.tree(), preparing, %{context | now: 2_000})
      assert finished.internal.casting == nil
      assert finished.internal.blackboard.pet.returning == :command
    end

    test "returns to the saved Stay position after the commanded victim dies", %{pet: pet, target: target} do
      pet = pet |> PetBT.command(:stay, 0, 1_000) |> PetBT.command(:attack, target, 1_000)
      pet = %{pet | movement_block: %{pet.movement_block | position: {20.0, 2.0, 0.0, 0.0}}}
      context = context(pet, target, alive?: false)
      assert {:success, returning} = BT.tick(PetBT.tree(), pet, context)
      assert returning.internal.blackboard.pet.returning == :combat
      refute returning.internal.pet.attack_command?
      assert returning.internal.in_combat
      assert returning.internal.blackboard.combat.attack_started == false

      assert {{:running, _}, returning} = BT.tick(PetBT.tree(), returning, context)
      assert [%NavigationIntent{destination: {+0.0, 2.0, +0.0}}] = returning.internal.navigation_intents
      moved = NavigationResolver.resolve(returning, 1_000, fn _, _, destination, _ -> [destination] end)
      arrived_at = moved.internal.movement_start_time + moved.movement_block.duration
      assert is_integer(arrived_at)
      assert {:success, arrived} = BT.tick(PetBT.tree(), moved, %{context | now: arrived_at})
      assert {+0.0, 2.0, +0.0, _orientation} = arrived.movement_block.position
      assert arrived.internal.blackboard.pet.returning == nil
      assert arrived.internal.pet.command_state == :stay
    end

    test "a partial return path never counts as arrival and is retried", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      pet = %{pet | movement_block: %{pet.movement_block | position: {20.0, 2.0, 0.0, 0.0}}}
      pet = PetBT.clear_combat_state(pet, 1_000)
      context = context(pet, target)
      {{:running, _}, returning} = BT.tick(PetBT.tree(), pet, context)
      partial = NavigationResolver.resolve(returning, 1_000, fn _, _, _, _ -> [{10.0, 2.0, 0.0}] end)
      arrived_at = partial.internal.movement_start_time + partial.movement_block.duration
      assert {{:running, _}, retrying} = BT.tick(PetBT.tree(), partial, %{context | now: arrived_at})
      assert retrying.internal.blackboard.pet.returning == :combat
      assert [%NavigationIntent{destination: {+0.0, 2.0, +0.0}}] = retrying.internal.navigation_intents
    end

    test "Follow suppresses proximity acquisition until the pet reaches its owner", %{pet: pet, target: target} do
      pet = %{pet | movement_block: %{pet.movement_block | position: {20.0, 2.0, 0.0, 0.0}}}
      pet = PetBT.command(pet, :follow, 0, 1_000)
      context = context(pet, target)
      assert {{:running, _}, returning} = BT.tick(PetBT.tree(), pet, context)
      refute returning.internal.in_combat
      assert returning.unit.target == 0
      assert [%NavigationIntent{destination: {x, 2.0, +0.0}}] = returning.internal.navigation_intents
      assert_in_delta x, 0.0, 0.01
      refute Targeting.retaliation?(returning, target, context)

      moved = NavigationResolver.resolve(returning, 1_000, fn _, _, destination, _ -> [destination] end)
      context = %{context | now: moved.internal.movement_start_time + moved.movement_block.duration}
      assert {:success, arrived} = BT.tick(PetBT.tree(), moved, context)
      assert arrived.internal.blackboard.pet.returning == nil
      assert {:success, attacking} = BT.tick(PetBT.tree(), arrived, context)
      assert attacking.unit.target == target
      refute attacking.internal.pet.attack_command?
    end

    test "Stay does not chase an automatic victim that leaves melee reach", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :stay, 0, 1_000)
      %{entity: pet} = Engagement.enter(pet, target, 1_000, selection: :target)
      assert {{:running, _}, staying} = BT.tick(PetBT.tree(), pet, context(pet, target))
      assert staying.internal.navigation_intents == []
      assert staying.movement_block.position == pet.movement_block.position
      assert staying.unit.target == target
    end
  end

  describe "enter/4" do
    test "damage cannot interrupt a commanded recall but natural returns permit defense", %{pet: pet, target: target} do
      recalled = PetBT.command(pet, :follow, 0, 1_000)
      damaged = Entity.take_damage(recalled, 10, 1_001, source: target)
      assert damaged.unit.health == 90
      assert damaged.internal.in_combat
      assert damaged.unit.target == 0
      assert damaged.internal.blackboard.pet.returning == :command

      returning = PetBT.clear_combat_state(pet, 1_000)
      assert Targeting.retaliation?(returning, target, context(returning, target))

      assert %Engagement.Result{entity: defended, to: :engaged} =
               Engagement.enter(returning, target, 1_001, ThreatSelection.opts(returning))

      assert defended.internal.blackboard.pet.returning == nil
    end

    test "death clears return progress and explicit Attack", %{pet: pet, target: target} do
      pet = PetBT.command(pet, :attack, target, 1_000)
      dead = Entity.take_damage(pet, 100, 1_001, source: target)
      refute dead.internal.pet.attack_command?
      assert dead.internal.blackboard.pet.returning == nil

      recalled = PetBT.command(pet, :follow, 0, 1_000)
      dead = Entity.take_damage(recalled, 100, 1_001, source: target)
      assert dead.internal.blackboard.pet.returning == nil
    end
  end

  defp pet(_context) do
    pet = %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, 1, 1)},
      unit: %Unit{health: 100, max_health: 100, level: 50, auras: [], flags: 0, bounding_radius: 0.5},
      movement_block: %MovementBlock{position: {0.0, 2.0, 0.0, 0.0}, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.open(999),
        creature: %Internal.Creature{},
        spellbook: %{},
        in_combat: false,
        blackboard: %Blackboard{},
        pet: %Pet{kind: :hunter, owner_guid: 1, reaction_state: :aggressive}
      }
    }

    %{pet: pet, target: Guid.from_low_guid(:mob, 17, 2)}
  end

  defp context(pet, target, extra \\ []) do
    world = pet.internal.world
    source = %FactionTemplate{id: 1, faction: 1, faction_group: 3, enemy_group: 12}
    enemy = %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}

    actors = %{
      pet.object.guid => %Observation{guid: pet.object.guid, metadata: %{faction_template: source}},
      1 => %Observation{guid: 1, position: {world, 0.0, 0.0, 0.0}, metadata: %{orientation: 0.0}},
      target => %Observation{
        guid: target,
        position: {world, 30.0, 2.0, 0.0},
        distance: 30.0,
        metadata: Map.merge(%{alive?: true, level: 10, faction_template: enemy}, Map.new(extra))
      }
    }

    perception = Perception.new(1_000, {world, 0.0, 2.0, 0.0}, actors, %{mobs: [{target, 30.0}]})
    Context.new(1_000, perception: perception)
  end
end
