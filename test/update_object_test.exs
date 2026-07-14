defmodule ThistleTea.UpdateObjectTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.UpdateObject

  describe "sanity check" do
    setup [:player, :unit, :object, :values_update, :create_object_update]

    test "flatten_field_structs/1", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit])
      assert Enum.any?(fields, fn {field, _value, _metadata} -> field == :coinage end)
      assert Enum.any?(fields, fn {field, _value, _metadata} -> field == :health end)
    end

    test "generate_mask/1", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit])
      mask = UpdateObject.generate_mask(fields)
      assert byte_size(mask) > 0
    end

    test "generate_objects/1", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit])
      objects = UpdateObject.generate_objects(fields)
      assert byte_size(objects) > 0
    end

    test "to_packet/1 - :values", %{values_update: values_update} do
      packet = UpdateObject.to_packet(values_update)
      assert byte_size(packet.payload) > 0
    end

    test "to_packet/1 - :create_object", %{create_object_update: create_object_update} do
      packet = UpdateObject.to_packet(create_object_update)
      assert byte_size(packet.payload) > 0
    end
  end

  describe "visibility filtering" do
    setup [:object, :unit, :player_with_private_fields, :create_object_update]

    test "to_list/2 :self includes private fields", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit], :self)
      field_names = Enum.map(fields, fn {f, _v, _m} -> f end)

      assert :coinage in field_names, "expected private :coinage to be included for :self"
      assert :head in field_names, "expected private :head to be included for :self"
      assert :xp in field_names, "expected private :xp to be included for :self"
      assert :strength in field_names, "expected private :strength to be included for :self"
    end

    test "zero combo points are encoded against the previous combo target" do
      player = %Player{field_combo_target: 77, combo_points: 0}
      fields = UpdateObject.flatten_field_structs([player], :self)

      assert {:field_combo_target, 77, _metadata} = Enum.find(fields, &match?({:field_combo_target, _, _}, &1))

      assert {:field_bytes, <<_flags, 0, _action_bars, _rank>>, _metadata} =
               Enum.find(fields, &match?({:field_bytes, _, _}, &1))
    end

    test "to_list/2 :other strips private fields", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit], :other)
      field_names = Enum.map(fields, fn {f, _v, _m} -> f end)

      refute :coinage in field_names, "expected private :coinage to be filtered for :other"
      refute :head in field_names, "expected private :head to be filtered for :other"
      refute :strength in field_names, "expected private :strength to be filtered for :other"
      refute :xp in field_names
      refute :rest_state_experience in field_names
    end

    test "to_list/2 :other keeps public fields", %{player: player, unit: unit} do
      fields = UpdateObject.flatten_field_structs([player, unit], :other)
      field_names = Enum.map(fields, fn {f, _v, _m} -> f end)

      assert :health in field_names
      assert :level in field_names
      assert :features in field_names
      assert :visible_item_1_0 in field_names, "visible item slot 0 (entry id) should be public"
    end

    test "to_packet/2 with recipient == owner produces larger packet than a different recipient", %{
      create_object_update: obj
    } do
      self_packet = UpdateObject.to_packet(obj, obj.object.guid)
      other_packet = UpdateObject.to_packet(obj, obj.object.guid + 1)

      assert byte_size(self_packet.payload) > byte_size(other_packet.payload),
             "expected non-owner packet to be smaller (private fields stripped)"
    end

    test "to_packet/2 with nil recipient defaults to full :self visibility", %{create_object_update: obj} do
      self_packet = UpdateObject.to_packet(obj, obj.object.guid)
      nil_packet = UpdateObject.to_packet(obj, nil)

      assert byte_size(self_packet.payload) == byte_size(nil_packet.payload)
    end

    test "mask sizes correctly when the highest-offset field has size > 1", %{object: object} do
      # visible_item_19_0 at 0x01DC has size 8: bits 476..483. Mask must include bit 483.
      player = %Player{
        gender: 1,
        skin: 1,
        face: 1,
        hair_style: 1,
        hair_color: 1,
        visible_item_19_0: 12_345
      }

      obj = %UpdateObject{
        update_type: :create_object,
        object_type: :player,
        movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
        object: object,
        player: player
      }

      # Without the bug fix this raises FunctionClauseError in Bitmap.Integer.set
      packet = UpdateObject.to_packet(obj, object.guid + 1)
      assert byte_size(packet.payload) > 0
    end

    test "to_packet/2 emits internally consistent mask + data for non-owner recipient", %{create_object_update: obj} do
      import Bitwise

      packet = UpdateObject.to_packet(obj, obj.object.guid + 1)
      <<1::little-32, 0, _update_type, rest::binary>> = packet.payload
      <<header, rest::binary>> = rest
      packed_size = Enum.reduce(0..7, 0, fn i, acc -> acc + (bsr(header, i) |> band(1)) end)
      <<_packed::binary-size(^packed_size), _obj_type, rest::binary>> = rest
      # update_flag=0 means no movement body
      <<_update_flag, mask_count, rest::binary>> = rest
      mask_bytes = mask_count * 4
      <<mask::binary-size(^mask_bytes), data::binary>> = rest
      set_bits = for(<<b::1 <- mask>>, do: b) |> Enum.sum()

      assert byte_size(data) == set_bits * 4
    end
  end

  defp values_update(context) do
    values_update = %UpdateObject{
      update_type: :values,
      object: context.object,
      player: context.player,
      unit: context.unit
    }

    {:ok, Map.put(context, :values_update, values_update)}
  end

  defp create_object_update(context) do
    create_object_update = %UpdateObject{
      update_type: :create_object,
      object_type: :player,
      movement_block: %MovementBlock{update_flag: 0, position: {0.0, 0.0, 0.0, 0.0}},
      object: context.object,
      player: context.player,
      unit: context.unit
    }

    {:ok, Map.put(context, :create_object_update, create_object_update)}
  end

  defp object(context) do
    object = %Object{
      guid: 123_456_789,
      type: 1,
      entry: 1001,
      scale_x: 1.0
    }

    {:ok, Map.put(context, :object, object)}
  end

  defp player(context) do
    player = %Player{
      gender: 1,
      skin: 1,
      face: 1,
      hair_style: 1,
      hair_color: 1,
      coinage: 500
    }

    {:ok, Map.put(context, :player, player)}
  end

  defp player_with_private_fields(context) do
    player = %Player{
      gender: 1,
      skin: 1,
      face: 1,
      hair_style: 1,
      hair_color: 1,
      coinage: 500,
      head: 0x4000000000003160,
      mainhand: 0x4000000000003161,
      xp: 42,
      next_level_xp: 100,
      rest_state_experience: 50,
      visible_item_1_0: 12_640
    }

    {:ok, Map.put(context, :player, player)}
  end

  defp unit(context) do
    unit = %Unit{
      health: 1000,
      power1: 100,
      power_type: 0,
      level: 10,
      race: 1,
      class: 1,
      gender: 1,
      strength: 50
    }

    {:ok, Map.put(context, :unit, unit)}
  end
end
