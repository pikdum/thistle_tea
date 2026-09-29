defmodule ThistleTea.Game.World.Loader.GameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Entity.GameObjectSpawn
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.World.Loader.GameObject, as: GameObjectLoader
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader

  setup [:rows]

  describe "game_object_spawn/1" do
    test "translates the spawn row's pose, state, respawn, and event", %{row: row} do
      assert GameObjectLoader.game_object_spawn(row) == %GameObjectSpawn{
               guid: 5000,
               entry: 161_557,
               map_id: 1,
               position: {1.0, 2.0, 3.0, 0.5},
               rotation: {0.0, 0.0, 0.25, 0.97},
               state: 1,
               anim_progress: 100,
               respawn_seconds: 180,
               event: 7
             }
    end
  end

  describe "build/1" do
    test "pairs the translated template and spawn", %{row: row} do
      go = GameObjectLoader.build(row)

      assert go.object.entry == 161_557
      assert go.movement_block.position == {1.0, 2.0, 3.0, 0.5}
      assert go.internal.loot.id == 10_119
      assert go.internal.event == 7
    end
  end

  describe "GameObjectTemplate.build/1" do
    test "packs data columns in order and defaults missing gold", %{row: row} do
      assert %GameObjectTemplate{entry: 161_557, type: 3, min_gold: 0, max_gold: 0, data: data} =
               GameObjectTemplateLoader.build(row.game_object_template)

      assert length(data) == 24
      assert Enum.take(data, 3) == [43, 10_119, 0]
      assert List.last(data) == 5
    end
  end

  defp rows(_context) do
    template = %Mangos.GameObjectTemplate{
      entry: 161_557,
      type: 3,
      display_id: 3012,
      name: "Milly's Harvest",
      faction: 0,
      flags: 4,
      size: 1.0,
      data0: 43,
      data1: 10_119,
      data23: 5
    }

    row = %Mangos.GameObject{
      guid: 5000,
      id: 161_557,
      map: 1,
      position_x: 1.0,
      position_y: 2.0,
      position_z: 3.0,
      orientation: 0.5,
      rotation0: 0.0,
      rotation1: 0.0,
      rotation2: 0.25,
      rotation3: 0.97,
      state: 1,
      animprogress: 100,
      spawntimesecsmin: 180,
      game_object_template: template,
      game_event_game_object: %Mangos.GameEventGameObject{event: 7}
    }

    %{row: row}
  end
end
