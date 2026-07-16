defmodule ThistleTea.Game.World.Loader.AreaTriggerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.WorldRef

  describe "inside?/4" do
    test "checks distance against radius triggers" do
      trigger = %{map: 0, x: -9796.18, y: 157.773, z: 25.3878, radius: 9.0}

      assert AreaTrigger.inside?(trigger, 0, {-9796.0, 157.0, 25.0})
      assert AreaTrigger.inside?(trigger, 0, {-9790.0, 157.0, 30.0}, 5.0)
      refute AreaTrigger.inside?(trigger, 0, {-9700.0, 157.0, 25.0}, 5.0)
    end

    test "rejects other maps" do
      trigger = %{map: 0, x: 0.0, y: 0.0, z: 0.0, radius: 9.0}

      refute AreaTrigger.inside?(trigger, 1, {0.0, 0.0, 0.0})
    end

    test "checks oriented boxes when there is no radius" do
      trigger = %{
        map: 0,
        x: 0.0,
        y: 0.0,
        z: 0.0,
        radius: 0.0,
        box_x: 10.0,
        box_y: 4.0,
        box_z: 6.0,
        box_orientation: 0.0
      }

      assert AreaTrigger.inside?(trigger, 0, {4.0, 1.0, 2.0})
      refute AreaTrigger.inside?(trigger, 0, {6.0, 1.0, 2.0})
      refute AreaTrigger.inside?(trigger, 0, {4.0, 3.0, 2.0})
      refute AreaTrigger.inside?(trigger, 0, {4.0, 1.0, 4.0})
      assert AreaTrigger.inside?(trigger, 0, {6.0, 3.0, 4.0}, 2.0)
    end

    test "rotates the point into the box frame" do
      trigger = %{
        map: 0,
        x: 0.0,
        y: 0.0,
        z: 0.0,
        radius: 0.0,
        box_x: 10.0,
        box_y: 2.0,
        box_z: 6.0,
        box_orientation: :math.pi() / 2
      }

      assert AreaTrigger.inside?(trigger, 0, {0.0, 4.0, 0.0})
      refute AreaTrigger.inside?(trigger, 0, {4.0, 0.0, 0.0})
    end
  end

  describe "teleport/1" do
    @tag :vmangos_db
    test "loads Ragefire Chasm's patch-appropriate entrance" do
      assert %{
               required_level: 8,
               target_map: 389,
               x: 0.797643,
               y: -8.23429,
               z: -15.5288,
               orientation: 4.71239
             } = AreaTrigger.teleport(2230)
    end

    @tag :vmangos_db
    test "identifies Ragefire Chasm as an instance map" do
      assert AreaTrigger.instance_map?(389)
      refute AreaTrigger.instance_map?(1)
      refute AreaTrigger.spawnable_world?(WorldRef.open(389))
      assert AreaTrigger.spawnable_world?(WorldRef.instance(389, 1))
    end
  end
end
