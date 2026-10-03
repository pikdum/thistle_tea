defmodule ThistleTea.Game.World.Loader.Mob.BuilderTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder

  describe "build/2" do
    test "a creature drawn larger than its model reaches only by how much larger" do
      onyxia = build(display_scale: 2.0, native_display_scale: 1.8)

      assert_in_delta onyxia.unit.combat_reach, 26.0, 0.01
      assert_in_delta onyxia.unit.bounding_radius, 2.0, 0.01
      assert onyxia.unit.base_combat_reach == onyxia.unit.combat_reach
      assert onyxia.object.scale_x == 2.0
    end

    test "a creature drawn at its model's own size keeps the model's reach" do
      assert %Unit{combat_reach: 23.4, bounding_radius: 1.8} = build(display_scale: 1.8, native_display_scale: 1.8).unit
      assert %Unit{combat_reach: 23.4, bounding_radius: 1.8} = build(display_scale: 1.0, native_display_scale: nil).unit
    end
  end

  defp build(scales) do
    MobBuilder.build(
      struct!(
        %Mangos.Creature{
          guid: 1,
          id: 10_184,
          modelid: 8_570,
          curhealth: 100,
          creature_movement: [],
          creature_display_info_addon: %Mangos.CreatureDisplayInfoAddon{
            display_id: 8_570,
            bounding_radius: 1.8,
            combat_reach: 23.4
          },
          creature_template: %Mangos.CreatureTemplate{entry: 10_184, name: "Onyxia", speed_run: 1.0}
        },
        scales
      ),
      apply_addon_auras?: false
    )
  end
end
