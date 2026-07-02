defmodule ThistleTea.Game.Entity.Logic.MovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Movement

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
      spline_flags: Keyword.get(opts, :spline_flags, 0x100),
      spline_id: Keyword.get(opts, :spline_id),
      spline_start_position: Keyword.get(opts, :spline_start_position)
    }

    %{internal: internal, movement_block: movement_block}
  end

  test "moving? reflects movement window" do
    now = 5_000

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

    assert Movement.moving?(moving, now)
    refute Movement.moving?(not_moving, now)
  end

  test "remaining_move_duration/2 reflects explicit time" do
    now = 5_000

    entity =
      build_entity(
        start_time: now - 250,
        duration: 1_000
      )

    assert Movement.remaining_move_duration(entity, now) == 750
  end

  describe "next_spatial_update_delay/2" do
    test "returns the delay to the next spatial cell boundary" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{250.0, 0.0, 0.0}]
        )

      assert Movement.next_spatial_update_delay(entity, 0) == 4_980
    end

    test "returns the remaining duration when movement stays in the current cell" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{10.0, 0.0, 0.0}]
        )

      assert Movement.next_spatial_update_delay(entity, 0) == 10_000
    end

    test "returns zero without active movement" do
      entity = build_entity(start_time: nil, start_position: nil, spline_nodes: [])

      assert Movement.next_spatial_update_delay(entity, 0) == 0
    end
  end

  describe "time_to_within/4" do
    test "returns the delay until the path enters the radius" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{100.0, 0.0, 0.0}]
        )

      assert Movement.time_to_within(entity, {50.0, 0.0}, 3.0, 0) == 4_700
    end

    test "measures from the current position mid-move" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{100.0, 0.0, 0.0}]
        )

      assert Movement.time_to_within(entity, {80.0, 0.0}, 3.0, 5_000) == 2_700
    end

    test "returns the minimum delay when already within the radius" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{100.0, 0.0, 0.0}]
        )

      assert Movement.time_to_within(entity, {1.0, 0.0}, 3.0, 0) == 1
    end

    test "returns nil when the path never enters the radius" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 10_000,
          spline_nodes: [{100.0, 0.0, 0.0}]
        )

      assert Movement.time_to_within(entity, {50.0, 10.0}, 3.0, 0) == nil
    end

    test "walks across segments to find the contact point" do
      entity =
        build_entity(
          start_time: 0,
          start_position: {0.0, 0.0, 0.0},
          duration: 2_000,
          spline_nodes: [{10.0, 0.0, 0.0}, {10.0, 10.0, 0.0}]
        )

      assert Movement.time_to_within(entity, {10.0, 8.0}, 3.0, 0) == 1_500
    end

    test "returns nil without active movement" do
      entity = build_entity(start_time: nil, start_position: nil, spline_nodes: [])

      assert Movement.time_to_within(entity, {5.0, 0.0}, 3.0, 0) == nil
    end
  end

  test "sync_position updates time_passed while moving" do
    now = 5_000

    entity =
      build_entity(
        start_time: now - 10,
        start_position: {0.0, 0.0, 0.0},
        duration: 10_000,
        spline_nodes: [{0.0, 0.0, 0.0}]
      )

    updated = Movement.sync_position(entity, now)

    assert updated.movement_block.time_passed > 0
    assert updated.movement_block.time_passed < updated.movement_block.duration
    assert updated.movement_block.spline_nodes == [{0.0, 0.0, 0.0}]
    assert updated.internal.movement_start_time == entity.internal.movement_start_time
  end

  test "sync_position finalizes movement when complete" do
    now = 5_000

    entity =
      build_entity(
        start_time: now - 2_000,
        start_position: {0.0, 0.0, 0.0},
        duration: 1_000,
        spline_nodes: [{0.0, 0.0, 0.0}],
        spline_id: 7,
        spline_start_position: {0.0, 0.0, 0.0},
        movement_flags: 123,
        spline_flags: 0x100
      )

    updated = Movement.sync_position(entity, now)

    assert updated.movement_block.position == {0.0, 0.0, 0.0, 0.0}
    assert updated.movement_block.spline_nodes == []
    assert updated.movement_block.movement_flags == 0
    assert updated.movement_block.spline_flags == 0
    assert updated.movement_block.time_passed == updated.movement_block.duration
    assert is_nil(updated.movement_block.spline_id)
    assert is_nil(updated.movement_block.spline_start_position)
    assert is_nil(updated.internal.movement_start_time)
    assert is_nil(updated.internal.movement_start_position)
  end

  describe "position_at/4" do
    test "interpolates linearly along the path" do
      assert Movement.position_at({0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 500) == {5.0, 0.0, 0.0}
    end

    test "clamps before the start and after the end" do
      assert Movement.position_at({0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, -50) == {0.0, 0.0, 0.0}
      assert Movement.position_at({0.0, 0.0, 0.0}, [{10.0, 0.0, 0.0}], 1_000, 5_000) == {10.0, 0.0, 0.0}
    end

    test "walks across multiple segments" do
      nodes = [{10.0, 0.0, 0.0}, {10.0, 10.0, 0.0}]

      assert Movement.position_at({0.0, 0.0, 0.0}, nodes, 2_000, 1_500) == {10.0, 5.0, 0.0}
    end

    test "returns the start position without spline nodes" do
      assert Movement.position_at({1.0, 2.0, 3.0}, [], 1_000, 500) == {1.0, 2.0, 3.0}
    end
  end
end
