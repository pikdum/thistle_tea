defmodule ThistleTea.Game.Network.EmpathyUpdateTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell

  setup [:update]

  describe "to_packet/2" do
    test "caster receives damage and every resistance but no unrelated private fields", %{update: update} do
      for type <- [:values, :create_object, :create_object2] do
        fields = packet_fields(%{update | update_type: type}, 2)
        assert fields[0x0086] == <<12.5::little-float-size(32)>>
        assert fields[0x0087] == <<25.0::little-float-size(32)>>
        assert fields[0x0088] == <<3.0::little-float-size(32)>>
        assert fields[0x0089] == <<6.0::little-float-size(32)>>
        assert fields[0x008F] == <<0x1D::little-size(32)>>

        for {offset, resistance} <- Enum.zip(0x009B..0x00A1, [300, 0, 10, 20, 30, 40, 50]) do
          assert fields[offset] == <<resistance::little-size(32)>>
        end

        refute Map.has_key?(fields, 0x0096)
        refute Map.has_key?(fields, 0x00A2)
        refute Map.has_key?(fields, 0x00A5)
        refute Map.has_key?(fields, 0x00AD)
        assert fields[0x0016] == <<100::little-size(32)>>
      end
    end

    test "bystanders receive public fields and preserved loot flags", %{update: update} do
      fields = packet_fields(update, 3)
      assert fields[0x008F] == <<0x0D::little-size(32)>>
      assert fields[0x0016] == <<100::little-size(32)>>
      refute Map.has_key?(fields, 0x0086)
      refute Map.has_key?(fields, 0x009B)
      refute Map.has_key?(fields, 0x00A1)
    end

    test "removal clears the caster's tooltip flag and stops disclosing fields", %{update: update} do
      update = %{update | unit: %{update.unit | auras: []}}
      fields = packet_fields(update, 2)
      assert fields[0x008F] == <<0x0D::little-size(32)>>
      refute Map.has_key?(fields, 0x0086)
      refute Map.has_key?(fields, 0x009B)
    end

    test "self updates retain private and special fields", %{update: update} do
      for viewer <- [update.object.guid, nil] do
        fields = packet_fields(update, viewer)
        assert Map.has_key?(fields, 0x0086)
        assert Map.has_key?(fields, 0x009B)
        assert Map.has_key?(fields, 0x0096)
        assert Map.has_key?(fields, 0x00A5)
      end
    end

    test "special information does not reveal player inventory or money" do
      player = %Player{coinage: 10_000, xp: 1234, head: 123}
      fields = UpdateObject.flatten_field_structs([player], :special_info)
      refute List.keymember?(fields, :coinage, 0)
      refute List.keymember?(fields, :xp, 0)
      refute List.keymember?(fields, :head, 0)
    end

    test "sparse updates do not clear dynamic flags", %{update: update} do
      fields = packet_fields(%{update | unit: %Unit{health: 50}}, 2)
      refute Map.has_key?(fields, 0x008F)
      assert fields[0x0016] == <<50::little-size(32)>>
    end
  end

  defp packet_fields(update, viewer) do
    packed_guid = BinaryUtils.pack_guid(update.object.guid)
    guid_size = byte_size(packed_guid)
    packet = UpdateObject.to_packet(update, viewer)
    <<1::little-size(32), 0, type, ^packed_guid::binary-size(^guid_size), rest::binary>> = packet.payload
    rest = if type in [2, 3], do: binary_part(rest, 2, byte_size(rest) - 2), else: rest
    <<count, mask::little-size(count * 32), values::binary>> = rest
    offsets = Enum.filter(0..(count * 32 - 1), &((mask &&& 1 <<< &1) != 0))
    words = for <<word::binary-size(4) <- values>>, do: word
    assert length(offsets) == length(words)
    Map.new(Enum.zip(offsets, words))
  end

  defp update(_context) do
    unit = %Unit{
      health: 100,
      dynamic_flags: 0x1D,
      min_damage: 12.5,
      max_damage: 25.0,
      min_offhand_damage: 3.0,
      max_offhand_damage: 6.0,
      normal_resistance: 300,
      holy_resistance: 0,
      fire_resistance: 10,
      nature_resistance: 20,
      frost_resistance: 30,
      shadow_resistance: 40,
      arcane_resistance: 50,
      strength: 20,
      base_mana: 200,
      attack_power: 50,
      power_cost_modifier: <<0::size(224)>>,
      auras: [%Holder{spell: %Spell{id: 1462}, caster_guid: 2, auras: [%Aura{type: :empathy}]}]
    }

    update = %UpdateObject{
      update_type: :values,
      object_type: :unit,
      object: %Object{guid: 10},
      movement_block: %MovementBlock{update_flag: 0},
      unit: unit
    }

    %{update: update}
  end
end
