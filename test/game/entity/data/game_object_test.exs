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
      assert go.internal.world.map_id == 0
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

    test "hunter trap templates retain their trigger definition" do
      data = [12, 0, 5, 13_797, 1, 0, 0, 0] ++ List.duplicate(0, 16)

      template = %GameObjectTemplate{
        entry: 164_638,
        type: 6,
        display_id: 3074,
        name: "Immolation Trap",
        size: 1.0,
        flags: 0,
        faction: 0,
        data: data
      }

      trap = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0}, summoned_by: 99)

      assert trap.internal.trap.owner_guid == 99
      assert trap.internal.trap.spell_id == 13_797
      assert trap.internal.trap.radius == 2.5
      assert trap.internal.trap.charges == 1
    end

    test "summoning ritual templates retain target and participant data" do
      template = %GameObjectTemplate{
        entry: 36_727,
        type: 18,
        display_id: 1327,
        name: "Summoning Portal",
        size: 1.0,
        flags: 0,
        faction: 0,
        data: [3, 7720, 698, 0, 0, 0, 1, 0] ++ List.duplicate(0, 16)
      }

      portal =
        GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0},
          summoned_by: 99,
          ritual_target_guid: 123,
          ritual_zone_id: 12
        )

      assert portal.internal.ritual.owner_guid == 99
      assert portal.internal.ritual.target_guid == 123
      assert portal.internal.ritual.required_participants == 3
      assert portal.internal.ritual.completion_spell_id == 7720
      assert portal.internal.ritual.animation_spell_id == 698
      assert portal.internal.ritual.casters_grouped?
      refute portal.internal.ritual.persistent?
      assert portal.internal.ritual.zone_id == 12
      assert portal.internal.ritual.users == MapSet.new([99])
    end

    test "ritual templates retain their data-driven completion behavior" do
      template = %GameObjectTemplate{
        entry: 177_193,
        type: 18,
        display_id: 1327,
        name: "Doom Portal",
        size: 1.0,
        flags: 0,
        faction: 0,
        data: [5, 18_541, 18_540, 0, 20_625, 1, 1, 0] ++ List.duplicate(0, 16)
      }

      portal = GameObject.build_summoned(template, 0, {0.0, 0.0, 0.0, 0.0}, summoned_by: 99)

      assert portal.internal.ritual.required_participants == 5
      assert portal.internal.ritual.completion_spell_id == 18_541
      assert portal.internal.ritual.animation_spell_id == 18_540
      assert portal.internal.ritual.caster_target_spell_id == 20_625
      assert portal.internal.ritual.caster_target_spell_targets == 1
      assert portal.internal.ritual.casters_grouped?
    end
  end

  describe "build/1 chests" do
    defp bucket_row do
      %Mangos.GameObject{
        guid: 5000,
        id: 161_557,
        map: 0,
        position_x: 1.0,
        position_y: 2.0,
        position_z: 3.0,
        orientation: 0.0,
        rotation0: 0.0,
        rotation1: 0.0,
        rotation2: 0.0,
        rotation3: 1.0,
        state: 1,
        animprogress: 100,
        spawntimesecsmin: 180,
        spawntimesecsmax: 180,
        game_object_template: %Mangos.GameObjectTemplate{
          entry: 161_557,
          type: 3,
          display_id: 3012,
          name: "Milly's Harvest",
          faction: 0,
          flags: 4,
          size: 1.0,
          data0: 43,
          data1: 10_119,
          mingold: 0,
          maxgold: 0
        },
        game_event_game_object: nil
      }
    end

    test "carries loot config, respawn delay, and the activate dynamic flag" do
      go = GameObject.build(bucket_row())

      assert go.internal.loot.id == 10_119
      assert go.internal.loot.min_gold == 0
      assert go.internal.spawn.respawn_delay_ms == 180_000
      assert go.game_object.dyn_flags == 1
    end

    test "non-chest game objects carry no loot" do
      row = bucket_row()
      row = %{row | game_object_template: %{row.game_object_template | type: 5}}
      go = GameObject.build(row)

      assert go.internal.loot == nil
      assert go.internal.spawn == nil
      assert go.game_object.dyn_flags == 0
    end

    test "chair game objects carry their slot count and height" do
      row = bucket_row()

      row = %{
        row
        | game_object_template: %{
            row.game_object_template
            | type: 7,
              data0: 3,
              data1: 2
          }
      }

      go = GameObject.build(row)

      assert go.internal.chair.slots == 3
      assert go.internal.chair.height == 2
    end
  end
end
