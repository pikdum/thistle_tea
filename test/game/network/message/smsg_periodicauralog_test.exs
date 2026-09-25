defmodule ThistleTea.Game.Network.Message.SmsgPeriodicauralogTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message.SmsgPeriodicauralog

  describe "to_binary/1" do
    test "encodes resource leech as aura 64 with the conversion multiplier" do
      binary =
        SmsgPeriodicauralog.to_binary(%SmsgPeriodicauralog{
          target: 0x11,
          caster: 0x22,
          spell_id: 5138,
          auras: [%{aura_type: :periodic_mana_leech, misc_value: 3, amount: 50, multiplier: 0.5}]
        })

      assert binary ==
               <<1, 0x11, 1, 0x22, 5138::little-size(32), 1::little-size(32), 64::little-size(32), 3::little-size(32),
                 50::little-size(32), 0.5::little-float-size(32)>>
    end

    test "encodes percentage mana recovery as aura 21 with mana power type" do
      binary =
        SmsgPeriodicauralog.to_binary(%SmsgPeriodicauralog{
          target: 0x11,
          caster: 0x22,
          spell_id: 25_990,
          auras: [%{aura_type: :obs_mod_mana, misc_value: 0, amount: 50}]
        })

      assert binary ==
               BinaryUtils.pack_guid(0x11) <>
                 BinaryUtils.pack_guid(0x22) <>
                 <<25_990::little-size(32), 1::little-size(32), 21::little-size(32), 0::little-size(32),
                   50::little-size(32)>>
    end

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
