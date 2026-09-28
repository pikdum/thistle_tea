defmodule ThistleTea.Game.World.Loader.ModelGeometryTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.ModelGeometry

  describe "height/2" do
    test "normalizes collision height using model and display scale" do
      table = :ets.new(:geometry, [:set])

      ModelGeometry.load(
        [
          %{id: 50, collision_height: 1.913, model_scale: 1.0, display_scale: 1.0},
          %{id: 60, collision_height: 2.111, model_scale: 1.25, display_scale: 1.0},
          %{id: 59, collision_height: 1.653, model_scale: 1.0, display_scale: 1.35},
          %{id: 1, collision_height: 0.0, model_scale: 0.0, display_scale: 0.0}
        ],
        table
      )

      assert_in_delta ModelGeometry.height(50, table), 1.913, 0.001
      assert_in_delta ModelGeometry.height(60, table), 2.111 / 1.25 / 1.25, 0.001
      assert_in_delta ModelGeometry.height(59, table), 1.653 / 1.35, 0.001
      assert ModelGeometry.height(1, table) == 2.0
      assert ModelGeometry.height(999, table) == 2.0
    end
  end

  describe "load_addons/2" do
    test "normalizes reach and radius and retains display scale" do
      table = :ets.new(:geometry, [:set])
      ModelGeometry.load([%{id: 59, collision_height: 1.653, model_scale: 1.0, display_scale: 1.35}], table)
      addons = [%{display_id: 59, bounding_radius: 0.405, combat_reach: 2.025}]
      ModelGeometry.load_addons(addons, table)
      model = ModelGeometry.get(59, table)
      assert_in_delta model.scale, 1.35, 0.001
      assert_in_delta model.bounding_radius, 0.3, 0.001
      assert_in_delta model.combat_reach, 1.5, 0.001
      ModelGeometry.load_addons(addons, table)
      assert ModelGeometry.get(59, table) == model
    end
  end

  describe "load/2" do
    test "mount capability requires extended display data and a mountable model or race" do
      table = :ets.new(:mount_models, [:set])

      for {id, extra, model, race, expected} <- [
            {1, nil, 0x80, 4, false},
            {2, 2, 0x80, 0, true},
            {3, 3, 0, 4, true},
            {4, 4, 0, 0, false},
            {5, 5, 0, nil, true}
          ] do
        ModelGeometry.load(
          [
            %{
              id: id,
              extended_display_id: extra,
              model_flags: model,
              race_flags: race,
              model_scale: 1.0,
              display_scale: 1.0
            }
          ],
          table
        )

        assert ModelGeometry.get(id, table).can_mount? == expected
      end

      refute ModelGeometry.get(999, table).can_mount?
    end
  end
end
