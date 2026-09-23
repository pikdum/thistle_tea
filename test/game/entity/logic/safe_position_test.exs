defmodule ThistleTea.Game.Entity.Logic.SafePositionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.WorldRef

  describe "remember/1" do
    test "retains the last grounded position through falling, swimming, and transport" do
      character = character({1.0, 2.0, 3.0, 0.5}) |> SafePosition.remember()
      assert SafePosition.destination(character) == {1.0, 2.0, 3.0, 0.5}

      for movement <- [
            %MovementBlock{position: {10.0, 2.0, -100.0, 0.5}, movement_flags: 0x4000},
            %MovementBlock{position: {10.0, 2.0, 3.0, 0.5}, movement_flags: 0x200000},
            %MovementBlock{position: {10.0, 2.0, 3.0, 0.5}, transport_guid: 3, transport_position: {0, 0, 0, 0}}
          ] do
        updated = %{character | movement_block: movement} |> SafePosition.remember()
        assert SafePosition.destination(updated) == {1.0, 2.0, 3.0, 0.5}
      end
    end

    test "does not recall an anchor from another world" do
      character = character({1.0, 2.0, 3.0, 0.5}) |> SafePosition.remember()
      changed = %{character | internal: %{character.internal | world: WorldRef.open(1)}}
      assert SafePosition.destination(changed) == nil
    end

    test "samples moved ground positions only when they match terrain height" do
      character = character({1.0, 2.0, 3.0, 0.5}) |> SafePosition.remember([3.0])
      nearby = %{character | movement_block: %MovementBlock{position: {2.0, 2.0, 3.0, 0.5}}}
      refute SafePosition.needs_update?(nearby)

      moved = %{character | movement_block: %MovementBlock{position: {10.0, 2.0, -100.0, 0.5}}}
      assert SafePosition.needs_update?(moved)
      assert SafePosition.destination(SafePosition.remember(moved, [3.0])) == {1.0, 2.0, 3.0, 0.5}

      grounded = %{moved | movement_block: %MovementBlock{position: {10.0, 2.0, 3.5, 0.5}}}
      assert SafePosition.destination(SafePosition.remember(grounded, [3.0])) == {10.0, 2.0, 3.5, 0.5}
    end
  end

  defp character(position) do
    %Character{internal: %Internal{world: WorldRef.open(0)}, movement_block: %MovementBlock{position: position}}
  end
end
