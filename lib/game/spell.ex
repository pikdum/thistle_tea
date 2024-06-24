defmodule ThistleTea.Game.Spell do
  import ThistleTea.Util, only: [send_packet: 2]

  alias ThistleTea.DBC

  require Logger

  @cmsg_cast_spell 0x12E
  @cmsg_cancel_cast 0x12F

  @smsg_cast_result 0x130

  def handle_packet(@cmsg_cast_spell, body, state) do
    <<spell_id::little-size(32), _rest::binary>> = body
    # TODO: https://gtker.com/wow_messages/docs/spellcasttargets.html
    spell = DBC.get_by(Spell, id: spell_id) |> DBC.preload(:spell_cast_time)
    Logger.info("CMSG_CAST_SPELL: #{spell.name_en_gb}")

    packet = <<spell_id::little-size(32), 0::little-size(32)>>

    cast_timer =
      Process.send_after(
        self(),
        {:send_packet, @smsg_cast_result, packet},
        spell.spell_cast_time.base
      )

    {:continue, Map.put(state, :cast_timer, cast_timer)}
  end

  def handle_packet(@cmsg_cancel_cast, _body, state) do
    Logger.info("CMSG_CANCEL_CAST")

    # TODO: do i need to ack this?
    state =
      case Map.get(state, :cast_timer, nil) do
        nil ->
          state

        timer ->
          Process.cancel_timer(timer)
          Map.delete(state, :cast_timer)
      end

    {:continue, state}
  end
end
