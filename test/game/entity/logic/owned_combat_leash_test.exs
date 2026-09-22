defmodule ThistleTea.Game.Entity.Logic.OwnedCombatLeashTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Engagement
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CombatLeashes
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:creatures]

  describe "Engagement.enter/4" do
    test "shares creature ownership through direct contact death and a separate later fight", %{
      owner: owner,
      summon: summon
    } do
      owner = enter(owner, 1_000)
      summon = enter(summon, 2_000)
      assert CombatLeashes.last_extended_at(owner) == 2_000
      assert owner.internal.combat_leash.origin != summon.internal.combat_leash.origin
      summon = enter(summon, 9_000)
      assert CombatLeashes.last_extended_at(owner) == 9_000

      %{entity: owner} = Engagement.enter(owner, 99, 10_000, selection: :target)
      %{entity: dead} = Engagement.die(%{owner | unit: %{owner.unit | health: 0}})
      EventSink.emit_pending(dead, Context.new(self()))
      assert CombatLeashes.last_extended_at(summon) == 10_000
      assert CombatLeashes.last_extended_at(owner) == nil

      %{entity: owner} = Engagement.reset(owner)
      owner = owner |> EventSink.emit_pending(Context.new(self())) |> enter(20_000)
      summon = enter(summon, 30_000)
      assert CombatLeashes.last_extended_at(owner) == 20_000
      assert CombatLeashes.last_extended_at(summon) == 30_000
    end

    test "links a summon that fights before its owner without renewing its origin", %{owner: owner, summon: summon} do
      summon = enter(summon, 1_000)
      summon = enter(summon, 5_000)
      owner = enter(owner, 10_000)
      assert CombatLeashes.last_extended_at(summon) == 10_000
      assert summon.internal.combat_leash.origin == {10.0, 0.0, 0.0}
      assert owner.internal.combat_leash.origin == {0.0, 0.0, 0.0}
    end

    test "creature ownership takes precedence over assistance and respects world copies", %{
      owner: owner,
      summon: summon
    } do
      owner = enter(owner, 1_000)
      other = owner.internal.world |> mob(20.0) |> enter(2_000)
      source = CombatLeash.reference(other)
      summon = enter(summon, 3_000, leash_source: source)
      assert summon.internal.combat_leash.last_extended_at == nil
      assert CombatLeashes.last_extended_at(summon) == 1_000
      %{entity: summon} = Engagement.leave(summon, :evade)
      summon = EventSink.emit_pending(summon, Context.new(self()))
      summon = %{summon | internal: %{summon.internal | world: WorldRef.open(1)}} |> enter(4_000)
      assert CombatLeashes.last_extended_at(summon) == 4_000
      assert CombatLeashes.last_extended_at(owner) == 1_000
      %{entity: summon} = Engagement.leave(summon, :evade)
      EventSink.emit_pending(summon, Context.new(self()))
    end

    test "creator and player relationships do not share creature clocks", %{owner: owner, summon: summon} do
      owner = enter(owner, 1_000)

      for owner_guid <- [0, 1] do
        independent = %{summon | unit: %{summon.unit | summoned_by: owner_guid, created_by: owner.object.guid}}
        independent = enter(independent, 2_000)
        assert CombatLeashes.last_extended_at(independent) == 2_000
        assert CombatLeashes.last_extended_at(owner) == 1_000
        %{entity: independent} = Engagement.leave(independent, :evade)
        EventSink.emit_pending(independent, Context.new(self()))
      end
    end
  end

  describe "Engagement.leave/3" do
    test "idle owner despawn detaches its clock without discarding the summon", %{owner: owner, summon: summon} do
      summon = enter(summon, 1_000)
      %{entity: owner} = Engagement.leave(owner, :despawn)
      owner = EventSink.emit_pending(owner, Context.new(self()))
      owner = enter(owner, 5_000)
      assert CombatLeashes.last_extended_at(summon) == 1_000
      assert CombatLeashes.last_extended_at(owner) == 5_000
    end
  end

  defp enter(entity, now, opts \\ []) do
    %{entity: entity} = Engagement.enter(entity, 99, now, Keyword.put(opts, :selection, :target))
    EventSink.emit_pending(entity, Context.new(self()))
  end

  defp creatures(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    owner = mob(world, 0.0)
    summon = mob(world, 10.0)
    summon = %{summon | unit: %{summon.unit | summoned_by: owner.object.guid}}
    Entity.register(owner.object.guid)
    World.update_position(owner)
    Metadata.put(owner.object.guid, %{incarnation_id: owner.internal.spawn.incarnation_id, alive?: true})

    on_exit(fn ->
      World.remove_position(owner)
      Metadata.delete(owner.object.guid)
      CombatLeashes.stop_world(world)
    end)

    %{owner: owner, summon: summon}
  end

  defp mob(world, x) do
    incarnation = System.unique_integer([:positive])

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 7, incarnation)},
      unit: %Unit{health: 100, max_health: 100, flags: 0},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world, spawn: %Spawn{incarnation_id: incarnation}}
    }
  end
end
