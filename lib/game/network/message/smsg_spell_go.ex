defmodule ThistleTea.Game.Network.Message.SmsgSpellGo do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELL_GO

  alias ThistleTea.Util

  @cast_flags_ammo 0x20

  defstruct [
    :cast_item,
    :caster,
    :spell,
    :flags,
    :hits,
    :misses,
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
        hits: hits,
        misses: misses,
        targets: targets,
        ammo_display_id: ammo_display_id,
        ammo_inventory_type: ammo_inventory_type
      }) do
    hits = hits || []
    misses = misses || []

    hits_binary =
      Enum.reduce(hits, <<>>, fn guid, acc ->
        acc <> <<guid::little-size(64)>>
      end)

    misses_binary =
      Enum.reduce(misses, <<>>, fn miss, acc ->
        acc <> <<miss.guid::little-size(64), miss.reason::little-size(8)>>
      end)

    Util.pack_guid(cast_item) <>
      Util.pack_guid(caster) <>
      <<spell::little-size(32), flags::little-size(16), length(hits)::little-size(8)>> <>
      hits_binary <>
      <<length(misses)::little-size(8)>> <>
      misses_binary <>
      targets <>
      if Bitwise.band(flags, @cast_flags_ammo) == 0 do
        <<>>
      else
        <<ammo_display_id::little-size(32), ammo_inventory_type::little-size(32)>>
      end
  end
end
