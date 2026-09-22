defmodule ThistleTea.Game.Entity.Logic.CombatLeashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  describe "should_evade?/3" do
    test "anchors a patrol fight at its current location and waits more than twelve seconds" do
      mob = engage()
      refute CombatLeash.should_evade?(mob, 20_000)
      mob = at(mob, {1_060.0, 0.0, 0.0})
      refute CombatLeash.should_evade?(mob, 13_000)
      assert CombatLeash.should_evade?(mob, 13_001)
      refute CombatLeash.should_evade?(mob, 20_000, shared_time: 9_000)
      assert CombatLeash.should_evade?(mob, 21_001, shared_time: 9_000)
    end

    test "keeps combat while either the victim or the creature is near the combat origin" do
      mob = engage() |> at({1_100.0, 0.0, 0.0})
      world = mob.internal.world
      refute CombatLeash.should_evade?(mob, 20_000, victim_position: {world, 1_040.0, 0.0, 0.0})
      assert CombatLeash.should_evade?(mob, 20_000, victim_position: {world, 1_051.0, 0.0, 0.0})
      assert CombatLeash.should_evade?(mob, 20_000, victim_position: {WorldRef.instance(0, 1), 1_000.0, 0.0, 0.0})
    end

    test "uses one and a half attack distance when greater than the threat radius" do
      mob = engage() |> at({1_060.0, 0.0, 0.0})
      refute CombatLeash.should_evade?(mob, 20_000, attack_distance: 45.0)
      assert CombatLeash.should_evade?(at(mob, {1_068.0, 0.0, 0.0}), 20_000, attack_distance: 45.0)
    end

    test "applies explicit leash distance from the combat origin despite a fresh shared clock" do
      mob = engage()
      mob = %{mob | internal: %{mob.internal | creature: %Creature{leash_range: 30.0}}}
      refute CombatLeash.should_evade?(mob, 1_001, shared_time: 1_001)
      assert CombatLeash.should_evade?(at(mob, {1_031.0, 0.0, 0.0}), 1_001, shared_time: 1_001)
    end
  end

  describe "enter/3" do
    test "hostile contact extends the timer without moving the origin and a new fight changes its reference" do
      mob = engage()
      original = CombatLeash.reference(mob)
      %{entity: mob} = Engagement.enter(at(mob, {1_060.0, 0.0, 0.0}), 20, 10_000)
      assert mob.internal.combat_leash.origin == {1_000.0, 0.0, 0.0}
      refute CombatLeash.should_evade?(mob, 20_000)
      assert CombatLeash.reference(mob) == original
      %{entity: mob} = Engagement.leave(mob, :evade)
      assert CombatLeash.reference(mob) == nil
      assert %Effects.CombatLeashEvent{ref: original, event: :stop} in mob.internal.events
      %{entity: mob} = Engagement.enter(mob, 20, 21_000)
      assert CombatLeash.reference(mob).generation == original.generation + 1
      assert mob.internal.combat_leash.origin == {1_060.0, 0.0, 0.0}
    end
  end

  describe "on_damage/3" do
    test "ordinary periodic damage does not extend the leash but channeled ticks do" do
      mob = engage() |> at({1_100.0, 0.0, 0.0})
      spell = %Spell{id: 1, school: :shadow, attributes: MapSet.new()}
      damaged = Core.take_damage(mob, 1, 10_000, source: 20, periodic: true, spell: spell)
      assert damaged.unit.health == 99
      assert CombatLeash.should_evade?(damaged, 13_001)
      channel = %{spell | attributes: MapSet.new([:channeled])}
      damaged = Core.take_damage(mob, 1, 10_000, source: 20, periodic: true, spell: channel)
      refute CombatLeash.should_evade?(damaged, 13_001)
      assert Enum.any?(damaged.internal.events, &match?(%Effects.CombatLeashEvent{event: {:extend, 10_000}}, &1))
    end
  end

  describe "maintain/2" do
    test "extends during root, stun, confusion, or fear without emitting on every tick" do
      for {root, flags} <- [{true, 0}, {false, 0x40000}, {false, 0x400000}, {false, 0x800000}] do
        mob = engage() |> at({1_100.0, 0.0, 0.0})
        mob = %{mob | unit: %{mob.unit | flags: flags}, internal: %{mob.internal | rooted?: root, events: []}}
        mob = CombatLeash.maintain(mob, 20_000)
        refute CombatLeash.should_evade?(mob, 20_000)
        assert [%Effects.CombatLeashEvent{event: {:extend, 20_000}}] = mob.internal.events
        assert CombatLeash.maintain(mob, 20_100).internal.events == mob.internal.events
        mob = %{mob | unit: %{mob.unit | flags: 0}, internal: %{mob.internal | rooted?: false}}
        refute CombatLeash.should_evade?(mob, 32_000)
        assert CombatLeash.should_evade?(mob, 32_001)
      end
    end
  end

  defp engage do
    mob = %Mob{
      object: %Object{guid: 10},
      unit: %Unit{health: 100, max_health: 100, flags: 0, target: 0, level: 20},
      movement_block: %MovementBlock{position: {1_000.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spawn: %Spawn{position: {0.0, 0.0, 0.0}, incarnation_id: 1}}
    }

    %{entity: mob} = Engagement.enter(mob, 20, 1_000)
    mob
  end

  defp at(mob, {x, y, z}), do: %{mob | movement_block: %{mob.movement_block | position: {x, y, z, 0.0}}}
end
