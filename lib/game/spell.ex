defmodule ThistleTea.Game.Spell do
  import ThistleTea.Util, only: [send_packet: 2]

  alias ThistleTea.DBC

  require Logger

  @cmsg_cast_spell 0x12E
  @cmsg_cancel_cast 0x12F

  @smsg_cast_result 0x130

  def handle_packet(@cmsg_cast_spell, body, state) do
    <<spell_id::little-size(32), rest::binary>> = body
    # TODO: https://gtker.com/wow_messages/docs/spellcasttargets.html
    spell = DBC.get_by(Spell, id: spell_id) |> DBC.preload(:spell_cast_time)
    Logger.info("CMSG_CAST_SPELL: #{spell.name_en_gb}")

    packet = <<spell_id::little-size(32), 0::little-size(32)>>

    Process.send_after(
      self(),
      {:send_packet, @smsg_cast_result, packet},
      spell.spell_cast_time.base
    )

    {:continue, state}
  end
end
