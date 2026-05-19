defmodule ThistleTea.Game.World.System.CellActivatorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.System.CellActivator

  describe "activate/2" do
    test "loads newly activated cells once" do
      parent = self()
      loader = fn cell -> send(parent, {:loaded, cell}) end
      name = :"cell_activator_test_#{System.unique_integer([:positive])}"

      start_supervised!({CellActivator, name: name, loader: loader})

      CellActivator.activate([{0, 1, 2}, {0, 1, 3}], name)
      assert_receive {:loaded, {0, 1, 2}}
      assert_receive {:loaded, {0, 1, 3}}

      CellActivator.activate([{0, 1, 2}], name)
      refute_receive {:loaded, {0, 1, 2}}, 50
    end

    test "invalidate allows cells to load again" do
      parent = self()
      loader = fn cell -> send(parent, {:loaded, cell}) end
      name = :"cell_activator_test_#{System.unique_integer([:positive])}"

      start_supervised!({CellActivator, name: name, loader: loader})

      CellActivator.activate([{0, 1, 2}], name)
      assert_receive {:loaded, {0, 1, 2}}

      CellActivator.invalidate(name)
      CellActivator.activate([{0, 1, 2}], name)
      assert_receive {:loaded, {0, 1, 2}}
    end
  end
end
