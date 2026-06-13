defmodule ThistleTea.Game.Network.Message.SmsgPeriodicauralogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgPeriodicauralog

  describe "to_binary/1" do
    test "encodes periodic heal aura logs" do
      binary =
        SmsgPeriodicauralog.to_binary(%SmsgPeriodicauralog{
          target: 0x11,
          caster: 0x22,
          spell_id: 139,
          auras: [%{aura_type: :periodic_heal, amount: 25}]
        })

      assert binary ==
               BinaryUtils.pack_guid(0x11) <>
                 BinaryUtils.pack_guid(0x22) <>
                 <<139::little-size(32), 1::little-size(32), 8::little-size(32), 25::little-size(32)>>
    end

    test "encodes periodic energize aura logs" do
      binary =
        SmsgPeriodicauralog.to_binary(%SmsgPeriodicauralog{
          target: 0x11,
          caster: 0x22,
          spell_id: 430,
          auras: [%{aura_type: :periodic_energize, misc_value: 0, amount: 50}]
        })

      assert binary ==
               BinaryUtils.pack_guid(0x11) <>
                 BinaryUtils.pack_guid(0x22) <>
                 <<430::little-size(32), 1::little-size(32), 24::little-size(32), 0::little-size(32),
                   50::little-size(32)>>
    end
  end
end
