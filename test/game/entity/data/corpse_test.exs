defmodule ThistleTea.Game.Entity.Data.CorpseTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2, >>>: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.WorldRef

  defp fixture_character do
    %Character{
      object: %Object{guid: 42},
      unit: %Unit{race: 4, gender: 1, native_display_id: 50, display_id: 10_045},
      player: %Player{skin: 1, face: 2, hair_style: 3, hair_color: 4, facial_hair: 5},
      movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}},
      internal: %Internal{world: %WorldRef{map_id: 1}, area: 141, name: "Tester"}
    }
  end

  describe "guid_for/1" do
    test "uses the corpse high guid with the player's low guid" do
      corpse_guid = Corpse.guid_for(42)

      assert Guid.entity_type(corpse_guid) == :corpse
      assert Guid.low_guid(corpse_guid) == 42
    end
  end

  describe "build/2" do
    test "places the corpse at the character's position" do
      corpse = Corpse.build(fixture_character(), [])

      assert corpse.object.guid == Corpse.guid_for(42)
      assert corpse.corpse.owner == 42
      assert corpse.corpse.pos_x == 1.0
      assert corpse.corpse.pos_y == 2.0
      assert corpse.corpse.pos_z == 3.0
      assert corpse.corpse.facing == 0.5
      assert corpse.movement_block.position == {1.0, 2.0, 3.0, 0.5}
      assert corpse.internal.world.map_id == 1
    end

    test "uses the native display id and appearance bytes" do
      corpse = Corpse.build(fixture_character(), [])

      assert corpse.corpse.display_id == 50
      assert corpse.corpse.bytes_1 == <<0, 4, 1, 1>>
      assert corpse.corpse.bytes_2 == <<2, 3, 4, 5>>
    end
  end

  describe "update object packet" do
    test "builds a create packet for the corpse" do
      packet =
        fixture_character()
        |> Corpse.build([%ItemTemplate{entry: 1, display_id: 1000, inventory_type: 1}])
        |> Core.update_object()
        |> UpdateObject.to_packet()

      assert %Packet{payload: <<1::little-size(32), 0, 3, _rest::binary>>} = packet
    end
  end

  describe "pack_items/1" do
    test "packs display id and inventory type per slot" do
      templates = [
        %ItemTemplate{entry: 1, display_id: 1000, inventory_type: 1},
        nil,
        %ItemTemplate{entry: 2, display_id: 2000, inventory_type: 5}
      ]

      packed = Corpse.pack_items(templates)

      assert (packed &&& 0xFFFFFFFF) == 1000 + (1 <<< 24)
      assert (packed >>> 32 &&& 0xFFFFFFFF) == 0
      assert (packed >>> 64 &&& 0xFFFFFFFF) == 2000 + (5 <<< 24)
    end

    test "empty equipment packs to zero" do
      assert Corpse.pack_items(List.duplicate(nil, 19)) == 0
    end
  end
end
