defmodule ThistleTea.Game.Spell do
  import ThistleTea.Util, only: [send_packet: 2, unpack_guid: 1, pack_guid: 1]
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.DBC

  require Logger

  @cmsg_cast_spell 0x12E
  @cmsg_cancel_cast 0x12F

  @smsg_cast_result 0x130
  @smsg_spell_start 0x131
  @smsg_spell_go 0x132

  # @spell_cast_target_self 0x00000000
  @spell_cast_target_unit 0x00000002

  def cancel_spell(state) do
    case Map.get(state, :cast_timer, nil) do
      nil ->
        state

      timer ->
        Process.cancel_timer(timer)
        Map.delete(state, :cast_timer)
    end
  end

  def handle_packet(@cmsg_cast_spell, body, state) do
    <<spell_id::little-size(32), spell_cast_targets::binary>> = body

    <<spell_cast_target_flags::little-size(16), rest::binary>> = spell_cast_targets

    {unit_target, rest} =
      if spell_cast_target_flags &&& @spell_cast_target_unit do
        unpack_guid(rest)
      else
        {nil, rest}
      end

    spell = DBC.get_by(Spell, id: spell_id) |> DBC.preload(:spell_cast_time)
    Logger.info("CMSG_CAST_SPELL: #{spell.name_en_gb} - #{spell_id}", target_name: unit_target)

    cast_result = <<spell_id::little-size(32), 0::little-size(32)>>

    state = cancel_spell(state)

    spell_start_flags = 0x2

    spell_start =
      state.packed_guid <>
        state.packed_guid <>
        <<
          spell_id::little-size(32),
          # cast flags
          spell_start_flags::little-size(16),
          # timer
          spell.spell_cast_time.base::little-size(32)
        >> <>
        spell_cast_targets

    # TODO: should broadcast this
    send_packet(@smsg_spell_start, spell_start)

    # unknown9
    spell_go_flags = 0x100

    spell_go =
      state.packed_guid <>
        state.packed_guid <>
        <<
          spell_id::little-size(32),
          # flags
          spell_go_flags::little-size(16),
          # number of hits
          1::little-size(8),
          # guid
          unit_target::little-size(64),
          # miss
          0
        >> <>
        spell_cast_targets

    spell_go_timer =
      Process.send_after(
        self(),
        {:send_packet, @smsg_spell_go, spell_go},
        spell.spell_cast_time.base
      )

    # TODO: refactor
    cast_timer =
      Process.send_after(
        self(),
        {:send_packet, @smsg_cast_result, cast_result},
        spell.spell_cast_time.base
      )

    {:continue, Map.put(state, :cast_timer, cast_timer)}
  end

  def handle_packet(@cmsg_cancel_cast, _body, state) do
    Logger.info("CMSG_CANCEL_CAST")
    state = cancel_spell(state)
    {:continue, state}
  end
end
