defmodule ThistleTea.UpdateObjectTest do
  use ExUnit.Case

  alias ThistleTea.Game.Utils.UpdateObject
  alias ThistleTea.Game.Utils.MovementBlock
  alias ThistleTea.Game.Entities.Data.Object
  alias ThistleTea.Game.Entities.Data.Player
  alias ThistleTea.Game.Entities.Data.Unit

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
      assert byte_size(packet) > 0
    end

    test "to_packet/1 - :create_object", %{create_object_update: create_object_update} do
      packet = UpdateObject.to_packet(create_object_update)
      assert byte_size(packet) > 0
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

  defp unit(context) do
    unit = %Unit{
      health: 1000,
      power1: 100,
      power_type: 0,
      level: 10,
      race: 1,
      class: 1,
      gender: 1
    }

    {:ok, Map.put(context, :unit, unit)}
  end
end
