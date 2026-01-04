defmodule ThistleTea.Game.Entity.Logic.MovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Time

  defp build_entity(opts) do
    internal = %Internal{
      map: 0,
      movement_start_time: Keyword.get(opts, :start_time),
      movement_start_position: Keyword.get(opts, :start_position)
    }

    movement_block = %MovementBlock{
      position: Keyword.get(opts, :position, {0.0, 0.0, 0.0, 0.0}),
      duration: Keyword.get(opts, :duration, 1_000),
      spline_nodes: Keyword.get(opts, :spline_nodes, []),
      time_passed: Keyword.get(opts, :time_passed, 0),
      movement_flags: Keyword.get(opts, :movement_flags, 1),
      spline_flags: Keyword.get(opts, :spline_flags, 0x100)
    }

    %{internal: internal, movement_block: movement_block}
  end

  test "is_moving? reflects movement window" do
    now = Time.now()

    moving =
      build_entity(
        start_time: now - 50,
        duration: 1_000
      )

    not_moving =
      build_entity(
        start_time: now - 2_000,
        duration: 1_000
      )

    assert Movement.is_moving?(moving)
    refute Movement.is_moving?(not_moving)
  end

  test "sync_position updates time_passed while moving" do
    now = Time.now()

    entity =
      build_entity(
        start_time: now - 10,
        start_position: {0.0, 0.0, 0.0},
        duration: 10_000,
        spline_nodes: [{0.0, 0.0, 0.0}]
      )

    updated = Movement.sync_position(entity)

    assert updated.movement_block.time_passed > 0
    assert updated.movement_block.time_passed < updated.movement_block.duration
    assert updated.movement_block.spline_nodes == [{0.0, 0.0, 0.0}]
    assert updated.internal.movement_start_time == entity.internal.movement_start_time
  end

  test "sync_position finalizes movement when complete" do
    now = Time.now()

    entity =
      build_entity(
        start_time: now - 2_000,
        start_position: {0.0, 0.0, 0.0},
        duration: 1_000,
        spline_nodes: [{0.0, 0.0, 0.0}],
        movement_flags: 123,
        spline_flags: 0x100
      )

    updated = Movement.sync_position(entity)

    assert updated.movement_block.position == {0.0, 0.0, 0.0, 0.0}
    assert updated.movement_block.spline_nodes == []
    assert updated.movement_block.movement_flags == 0
    assert updated.movement_block.spline_flags == 0
    assert updated.movement_block.time_passed == updated.movement_block.duration
    assert is_nil(updated.internal.movement_start_time)
    assert is_nil(updated.internal.movement_start_position)
  end
end
