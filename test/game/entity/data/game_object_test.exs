defmodule ThistleTea.Game.Entity.Data.GameObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Guid

  defp lightwell_template do
    GameObjectTemplate.build(%Mangos.GameObjectTemplate{
      entry: 181_102,
      type: 22,
      display_id: 6671,
      name: "Lightwell",
      faction: 0,
      flags: 0,
      size: 1.35,
      data0: 7001,
      data1: 5
    })
  end

  describe "build_summoned/4" do
    test "builds a spellcaster game object with use spell, charges, owner, and despawn" do
      go =
        GameObject.build_summoned(lightwell_template(), 0, {1.0, 2.0, 3.0, 0.5},
          summoned_by: 99,
          despawn_in_ms: 180_000
        )

      assert go.object.entry == 181_102
      assert Guid.type_id(go.object.guid) == :game_object
      assert go.game_object.display_id == 6671
      assert go.game_object.type_id == 22
      assert go.movement_block.position == {1.0, 2.0, 3.0, 0.5}
      assert go.internal.map == 0
      assert go.internal.summon.owner_guid == 99
      assert go.internal.summon.spell_id == 7001
      assert go.internal.summon.charges == 5
      assert go.internal.summon.despawn_in_ms == 180_000
    end

    test "summoned guids are unique per call" do
      template = lightwell_template()
      a = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0}, [])
      b = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0}, [])

      assert a.object.guid != b.object.guid
    end

    test "non-spellcaster templates carry no use spell" do
      template = %{lightwell_template() | type: 5}
      go = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0}, [])

      assert go.internal.summon.spell_id == nil
      assert go.internal.summon.charges == nil
    end
  end
end
