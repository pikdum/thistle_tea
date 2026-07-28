defmodule ThistleTea.Game.Network.Message.SmsgSpellCastTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell.Target

  test "spell start appends projectile metadata when the ammo flag is set" do
    message = %Message.SmsgSpellStart{
      cast_item: <<1>>,
      caster: <<1>>,
      spell: 75,
      flags: 0x22,
      timer: 0,
      targets: Target.none(),
      ammo_display_id: 5996,
      ammo_inventory_type: 24
    }

    binary = Message.SmsgSpellStart.to_binary(message)

    assert binary_part(binary, byte_size(binary) - 8, 8) ==
             <<5996::little-size(32), 24::little-size(32)>>
  end

  test "spell go appends projectile metadata when the ammo flag is set" do
    message = %Message.SmsgSpellGo{
      cast_item: 1,
      caster: 1,
      spell: 75,
      flags: 0x120,
      hits: [2],
      misses: [],
      targets: Target.unit(2),
      ammo_display_id: 5996,
      ammo_inventory_type: 24
    }

    binary = Message.SmsgSpellGo.to_binary(message)

    assert binary_part(binary, byte_size(binary) - 8, 8) ==
             <<5996::little-size(32), 24::little-size(32)>>
  end
end
