defmodule ThistleTea.Game.Entity.Logic.ChargeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Charge
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  describe "approach_path/4" do
    test "stops before the target hitbox while preserving intermediate path nodes" do
      assert Charge.approach_path([{6.0, 0.0, 0.0}, {6.0, 8.0, 0.0}], {0.0, 0.0, 0.0}, {6.0, 8.0, 0.0}, 4.5) ==
               [{6.0, 0.0, 0.0}, {6.0, 3.5, 0.0}]

      assert Charge.approach_path([{2.0, 0.0, 0.0}], {0.0, 0.0, 0.0}, {2.0, 0.0, 0.0}, 4.5) == []
    end
  end

  describe "start/2" do
    test "a queued charge cannot move a newly dead or rooted owner" do
      for entity <- entities() do
        dead = %{entity | unit: %{entity.unit | health: 0}}
        assert Charge.start(dead, command()) == dead
        {rooted, _} = Aura.apply_spell(entity, 2, 60, root(), 900)
        assert Charge.start(rooted, command()) == rooted
      end
    end
  end

  describe "reconcile/2" do
    test "player and creature charges defer new roots and stuns until arrival" do
      for entity <- entities(), type <- [:mod_root, :mod_stun] do
        charging = Charge.start(entity, command())
        {rooted, events} = Aura.apply_spell(charging, 2, 60, root(type), 1_100)
        assert Charge.active?(rooted, 1_100)
        refute Movement.blocked?(rooted)
        refute Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: true}, &1))
        assert Movement.completion_at(rooted) == 2_000
        arrived = Charge.reconcile(rooted, 2_000)
        assert arrived.movement_block.position == {10.0, 0.0, 0.0, 0.0}
        assert Movement.blocked?(arrived)
        assert arrived.internal.charge == nil
        assert Enum.any?(arrived.internal.events, &match?(%Effects.MovementRootChanged{rooted?: true}, &1))
        assert Charge.reconcile(arrived, 2_001) == arrived
      end
    end

    test "a removed pending root does not reappear on arrival" do
      for entity <- entities() do
        {rooted, _} = entity |> Charge.start(command()) |> Aura.apply_spell(2, 60, root(), 1_100)
        {cleansed, _} = Aura.remove_spells(rooted, [13_138], 1_200)
        arrived = Charge.reconcile(cleansed, 2_000)
        refute Movement.blocked?(arrived)
        assert arrived.unit.auras == []
        assert arrived.internal.charge == nil
      end
    end

    test "death ends the charge without moving the corpse on a late arrival" do
      for entity <- entities() do
        charging = entity |> Charge.start(command()) |> Movement.sync_position(1_250)
        dead = Core.take_damage(charging, 100, 1_250)
        assert dead.internal.charge == nil
        position = dead.movement_block.position
        ended = Charge.reconcile(dead, 1_250)
        assert ended.unit.health == 0
        assert ended.movement_block.position == position
        assert ended.internal.charge == nil
        assert Charge.reconcile(ended, 2_000) == ended
      end
    end

    test "a superseding spline survives an old arrival" do
      for entity <- entities() do
        moved = entity |> Charge.start(command()) |> Movement.move_along_path([{30.0, 0.0, 0.0}], [], 1_250)
        refute Charge.active?(moved, 1_500)
        released = Charge.reconcile(moved, 2_000)
        assert released.internal.charge == nil
        assert released.movement_block == moved.movement_block
        assert Movement.moving?(released, 2_000)
      end
    end
  end

  describe "cancel/2" do
    test "interruption applies the pending root at the current position" do
      for entity <- entities() do
        {rooted, _} = entity |> Charge.start(command()) |> Aura.apply_spell(2, 60, root(), 1_100)
        cancelled = Charge.cancel(rooted, 1_500)
        assert cancelled.movement_block.position == {5.0, 0.0, 0.0, 0.0}
        assert Movement.blocked?(cancelled)
        assert cancelled.internal.charge == nil
        assert Charge.finish(cancelled, 2_000) == cancelled
      end
    end
  end

  describe "tick/3" do
    test "a creature's ordinary behavior resumes after the forced movement" do
      tree =
        BT.action(fn entity, blackboard, _context ->
          {:success, %{entity | unit: %{entity.unit | target: 42}}, blackboard}
        end)

      entity = entities() |> List.last() |> Charge.start(command())
      {{:running, 500, :charge}, charging} = BehaviorRunner.tick(tree, entity, Context.new(1_500))
      refute charging.unit.target == 42
      {:success, arrived} = BehaviorRunner.tick(tree, charging, Context.new(2_000))
      assert arrived.unit.target == 42
      assert arrived.internal.charge == nil
      assert arrived.movement_block.position == {10.0, 0.0, 0.0, 0.0}
    end
  end

  defp entities do
    unit = %Unit{health: 100, max_health: 100, level: 60, auras: []}
    internal = %Internal{world: WorldRef.open(0), running: true, spline_id: 0}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0, run_speed: 7.0, walk_speed: 2.5}

    [
      %Character{object: %Object{guid: 1}, player: %Player{}, unit: unit, internal: internal, movement_block: movement},
      %Mob{object: %Object{guid: 1}, unit: unit, internal: internal, movement_block: movement}
    ]
  end

  defp command, do: %Commands.ChargePathResolved{path: [{10.0, 0.0, 0.0}], duration_ms: 1_000, started_at: 1_000}

  defp root(type \\ :mod_root) do
    %Spell{id: 13_138, duration_ms: 20_000, effects: [%Effect{index: 0, type: :apply_aura, aura: type}]}
  end
end
