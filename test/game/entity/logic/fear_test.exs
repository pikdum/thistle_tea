defmodule ThistleTea.Game.Entity.Logic.FearTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Fear, as: FearBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet, as: PetBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:mob]

  describe "destination_request/3" do
    test "scales panic runs with caster proximity", %{mob: mob} do
      mob = apply_fear(mob)

      for {distance, length} <- [{0.0, 11.2}, {10.0, 7.2}, {30.0, 6.0}, {50.0, 4.0}] do
        perception = perception(mob.internal.world, distance)
        assert {0, {x, y, z}, 5.0} = Fear.destination_request(mob, perception, Random.fixed(0.0))
        assert_in_delta x, length, 0.0001
        assert y == 0.0
        assert z == 0.0
      end
    end

    test "uses the current position and ignores casters in other copies", %{mob: mob} do
      mob = apply_fear(mob)
      mob = %{mob | movement_block: %{mob.movement_block | position: {100.0, 0.0, 0.0, 0.0}}}
      other_copy = perception(WorldRef.instance(0, 1), 105.0)
      assert {0, {x, y, z}, 5.0} = Fear.destination_request(mob, other_copy, Random.fixed(0.0))
      assert_in_delta x, 111.2, 0.0001
      assert {y, z} == {0.0, 0.0}
    end

    test "bounds the search even when the caster is missing", %{mob: mob} do
      mob = apply_fear(mob)
      assert {0, {x, y, z}, radius} = Fear.destination_request(mob, Perception.empty(), Random.fixed(0.999))
      assert z == 0.0
      assert_in_delta :math.sqrt(x * x + y * y) + radius, 30.0, 0.0001
    end
  end

  describe "tick/3" do
    test "wild creatures and pets run instead of using the confusion anchor", %{mob: mob} do
      for {tree, pet} <- [{MobBT.tree(), nil}, {PetBT.tree(), %Pet{owner_guid: 3}}] do
        mob = %{mob | internal: %{mob.internal | pet: pet}}
        mob = apply_fear(mob)
        {status, mob} = BehaviorRunner.tick(tree, mob, context(0))
        assert status == {:running, 0, :navigation}
        assert mob.internal.running
        assert mob.internal.blackboard.navigation.confused_anchor == nil
        assert mob.internal.blackboard.fear.moving?

        mob = resolve(mob, 0)
        assert mob.movement_block.spline_nodes == [{14.0, 0.0, 0.0}]
        assert mob.movement_block.duration == 2_000
        assert Enum.any?(mob.internal.events, &is_struct(&1, Effects.MonsterMove))
      end
    end

    test "pauses after arrival and requests a new run when ready", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {status, _mob} = BT.tick(tree(), mob, context(1_000))
      assert match?({:running, _, :movement}, status)

      mob = Movement.sync_position(mob, 2_001)
      assert {{:running, 800, :fear}, mob} = BT.tick(tree(), mob, context(2_001))
      refute Fear.ready?(mob, 2_800)
      assert Fear.ready?(mob, 2_801)
      assert {{:running, 0, :navigation}, mob} = BT.tick(tree(), mob, context(2_801, {28.0, 0.0, 0.0}))
      assert [%{destination: destination}] = mob.internal.navigation_intents
      assert destination == {28.0, 0.0, 0.0}
    end

    test "retries unavailable navigation without attacking or spinning", %{mob: mob} do
      mob = apply_fear(mob)
      assert {{:running, 1_000, :fear}, mob} = BT.tick(tree(), mob, context(0, nil))
      assert mob.internal.navigation_intents == []
      refute Fear.ready?(mob, 999)
      assert Fear.ready?(mob, 1_000)
    end

    test "failed paths retain fear and wait before retrying", %{mob: mob} do
      mob = apply_fear(mob)
      {_, mob} = BT.tick(tree(), mob, context(0))
      mob = NavigationResolver.resolve(mob, 0, fn _, _, _, _ -> nil end)
      assert {{:running, 800, :fear}, mob} = BT.tick(tree(), mob, context(1))
      assert Fear.active?(mob)
      assert mob.internal.navigation_intents == []
    end

    test "caps the traversed path when navigation returns a distant point", %{mob: mob} do
      mob = apply_fear(mob)
      {_, mob} = BT.tick(tree(), mob, context(0, {50.0, 50.0, 0.0}))

      mob =
        NavigationResolver.resolve(mob, 0, fn _map, _from, _to, _opts ->
          [{10.0, 0.0, 0.0}, {10.0, 10.0, 0.0}, {50.0, 50.0, 0.0}]
        end)

      [first, second, {x, y, z}] = mob.movement_block.spline_nodes
      assert first == {10.0, 0.0, 0.0}
      assert second == {10.0, 10.0, 0.0}
      assert_in_delta x, 10.0 + 10.0 / :math.sqrt(2), 0.0001
      assert_in_delta y, x, 0.0001
      assert z == 0.0
      assert_in_delta mob.movement_block.duration, 30.0 / 7.0 * 1_000, 1.0
      assert [%Effects.MonsterMove{move_opts: []}] = mob.internal.events
    end

    test "roots and stuns halt runs and fear resumes after removal", %{mob: mob} do
      for type <- [:mod_root, :mod_stun] do
        mob = mob |> apply_fear() |> moving()
        {mob, events} = Aura.apply_spell(mob, 3, 50, control_spell(2, type), 500)
        assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
        {status, mob} = BT.tick(tree(), mob, context(600))
        assert status == {:running, 500, :fear}
        assert mob.internal.navigation_intents == []
        refute Fear.ready?(mob, 600)

        {mob, _events} = Aura.remove_spells(mob, [2], 700)
        {_, mob} = BT.tick(tree(), mob, context(700))
        assert {{:running, 0, :navigation}, _mob} = BT.tick(tree(), mob, context(1_500))
      end
    end
  end

  describe "reconcile/4" do
    test "recklessness suspends fear without removing it and removal resumes it", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {mob, events} = Aura.apply_spell(mob, 3, 50, control_spell(2, :prevent_fleeing), 500)
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      assert Aura.has_aura?(mob, :mod_fear)
      refute Fear.active?(mob)
      refute Aura.crowd_controlled?(mob)
      assert mob.internal.blackboard.fear == nil
      assert Bitwise.band(mob.unit.flags, 0x00800000) == 0
      assert {:failure, _mob} = BT.tick(tree(), mob, context(500))

      {mob, _events} = Aura.remove_spells(mob, [2], 600)
      assert Fear.active?(mob)
      assert Aura.crowd_controlled?(mob)
      assert Fear.ready?(mob, 600)
      assert {{:running, 0, :navigation}, _mob} = BT.tick(tree(), mob, context(600))
    end

    test "fear applied under recklessness leaves casting intact until suppression ends", %{mob: mob} do
      {mob, _events} = Aura.apply_spell(mob, 3, 50, control_spell(2, :prevent_fleeing), 0)
      casting = %Cast{spell: %Spell{id: 3}}
      mob = %{mob | internal: %{mob.internal | casting: casting}}
      mob = apply_fear(mob)
      assert mob.internal.casting == casting
      refute Fear.active?(mob)

      {mob, _events} = Aura.remove_spells(mob, [2], 600)
      assert mob.internal.casting == nil
      assert Fear.active?(mob)
    end

    test "confusion takes over a fear run and removing it restores fear", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {mob, events} = Aura.apply_spell(mob, 3, 50, control_spell(2, :mod_confuse), 500)
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      assert mob.internal.blackboard.fear == nil
      refute Movement.moving?(mob, 500)
      {mob, _events} = Aura.remove_spells(mob, [2], 600)
      assert Fear.ready?(mob, 600)
    end

    test "application stops old movement and preserves combat and patrol state", %{mob: mob} do
      mob = Movement.move_along_path(mob, [{7.0, 0.0, 0.0}], [], 0)
      {mob, events} = Aura.apply_spell(mob, 2, 50, control_spell(1, :mod_fear), 500)
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      refute Movement.moving?(mob, 500)
      assert mob.internal.blackboard.navigation.target == nil
      assert mob.internal.blackboard.navigation.movement_override == :random
      assert mob.internal.threat == %{2 => 25.0}
      assert mob.unit.target == 2
      assert Bitwise.band(mob.unit.flags, 0x00800000) != 0
    end

    test "expiry clears fear memory in the actual behavior runner", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {_, mob} = BehaviorRunner.tick(tree(), mob, context(10_001))
      refute Fear.active?(mob)
      assert mob.internal.blackboard.fear == nil
      assert mob.internal.running == false
      refute Movement.moving?(mob, 10_001)
      assert Bitwise.band(mob.unit.flags, 0x00800000) == 0
    end

    test "dispel stops a run immediately and restores normal behavior", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {mob, events} = Aura.dispel(mob, 1, 500, :negative)
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      refute Fear.active?(mob)
      assert mob.internal.blackboard.fear == nil
      assert mob.internal.navigation_intents == []
      assert {:failure, _mob} = BT.tick(tree(), mob, context(500))
    end

    test "refresh and caster replacement discard old movement", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      {mob, events} = Aura.apply_spell(mob, 3, 50, control_spell(1, :mod_fear), 500)
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      assert Fear.source_guid(mob) == 3
      assert Fear.ready?(mob, 500)
      refute mob.internal.blackboard.fear.moving?
    end

    test "death clears fear without restoring stale navigation", %{mob: mob} do
      mob = mob |> apply_fear() |> moving()
      mob = Core.take_damage(mob, 1_000, 500, source: 2)
      assert mob.unit.health == 0
      refute Fear.active?(mob)
      assert mob.internal.blackboard.fear == nil
      assert mob.internal.navigation_intents == []
      refute Movement.moving?(mob, 500)
      assert Bitwise.band(mob.unit.flags, 0x00800000) == 0
    end
  end

  defp mob(_context) do
    mob = %Mob{
      object: %Object{guid: 10},
      unit: %Unit{health: 100, max_health: 100, level: 50, flags: 0, auras: [], target: 2},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0},
      internal: %Internal{
        world: WorldRef.open(0),
        running: false,
        threat: %{2 => 25.0},
        blackboard: %Blackboard{navigation: %Blackboard.Navigation{target: {1.0, 0.0, 0.0}, movement_override: :random}}
      }
    }

    %{mob: mob}
  end

  defp control_spell(id, aura) do
    %Spell{
      id: id,
      duration_ms: 10_000,
      dispel_type: 1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: aura, implicit_target_a: :target_enemy}]
    }
  end

  defp apply_fear(mob) do
    {mob, _events} = Aura.apply_spell(mob, 2, 50, control_spell(1, :mod_fear), 0)
    mob
  end

  defp moving(mob) do
    {_, mob} = BT.tick(tree(), mob, context(0))
    resolve(mob, 0)
  end

  defp resolve(mob, now) do
    NavigationResolver.resolve(mob, now, fn _map, _from, to, opts ->
      assert opts == [allow_steep: false]
      [to]
    end)
  end

  defp tree, do: BT.action(&FearBT.tick/3)

  defp context(now, destination \\ {14.0, 0.0, 0.0}) do
    Context.new(now, navigation: %{Navigation.empty() | fear_point: destination}, random: Random.fixed(0.0))
  end

  defp perception(world, x) do
    Perception.new(0, nil, %{2 => %Observation{guid: 2, position: {world, x, 0.0, 0.0}}}, %{})
  end
end
