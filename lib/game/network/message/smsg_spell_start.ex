defmodule ThistleTea.Game.Network.Message.SmsgSpellStart do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELL_START

  @cast_flags_ammo 0x20

  defstruct [
    :cast_item,
    :caster,
    :spell,
    :flags,
    :timer,
    :targets,
    :ammo_display_id,
    :ammo_inventory_type
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        cast_item: cast_item,
        caster: caster,
        spell: spell,
        flags: flags,
        timer: timer,
        targets: targets,
        ammo_display_id: ammo_display_id,
        ammo_inventory_type: ammo_inventory_type
      }) do
    cast_item <>
      caster <>
      <<spell::little-size(32), flags::little-size(16), timer::little-size(32)>> <>
      targets <>
      if Bitwise.band(flags, @cast_flags_ammo) == 0 do
        <<>>
      else
        <<ammo_display_id::little-size(32), ammo_inventory_type::little-size(32)>>
      end
  end
end
