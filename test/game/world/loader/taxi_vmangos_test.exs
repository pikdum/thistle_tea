defmodule ThistleTea.Game.World.Loader.TaxiVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.World.Loader.Taxi

  @moduletag :vmangos_db

  describe "load_nodes/0" do
    test "loads the latest Vanilla node override and resolves mount displays" do
      assert %Node{} = node = Enum.find(Taxi.load_nodes(), &(&1.id == 2))
      assert node.name == "Stormwind, Elwynn"
      assert node.position == {-8840.56, 489.7, 109.61}
      assert node.mount_display_ids == %{alliance: 6852, horde: 0}
    end
  end

  describe "load_transitions/0" do
    test "loads transitions available to build 5875" do
      transitions = Taxi.load_transitions()
      assert transitions[{499, 482}] == {20, 1}
      assert transitions[{500, 363}] == {17, 2}
      assert map_size(transitions) == 355
    end
  end
end
