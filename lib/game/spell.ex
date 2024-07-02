defmodule ThistleTea.Game.Spell do
  import ThistleTea.Util, only: [send_packet: 2, unpack_guid: 1, within_range: 2]
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.DBC

  require Logger

  @cmsg_cast_spell 0x12E
  @cmsg_cancel_cast 0x12F

  @smsg_cast_result 0x130
  @smsg_spell_start 0x131
  @smsg_spell_go 0x132
  @smsg_spell_failure 0x133
  @smsg_spell_failed_other 0x2A6

  @spell_cast_target_self 0x00000000
  @spell_cast_target_unit 0x00000002

  # @spell_failed_unknown 0x91
  @spell_failed_interrupted 0x23

  def cancel_spell(state, reason \\ @spell_failed_interrupted) do
    case Map.get(state, :spell) do
      nil ->
        state

      spell ->
        Process.cancel_timer(spell.cast_timer)

        send_packet(
          @smsg_cast_result,
          <<spell.spell_id::little-size(32), 2::little-size(8), reason::little-size(8)>>
        )

        send_packet(
          @smsg_spell_failure,
          <<state.guid::little-size(64), spell.spell_id::little-size(32), reason::little-size(8)>>
        )

        Registry.dispatch(ThistleTea.PlayerRegistry, state.character.map, fn entries ->
          %{x: x1, y: y1, z: z1} = state.character.movement

          for {pid, values} <- entries do
            {_guid, x2, y2, z2} = values

            if pid != self() and within_range({x1, y1, z1}, {x2, y2, z2}) do
              send(
                pid,
                {:send_packet, @smsg_spell_failed_other,
                 <<state.guid::little-size(64), spell.spell_id::little-size(32)>>}
              )
            end
          end
        end)

        Map.delete(state, :spell)
    end
  end

  def handle_packet(@cmsg_cast_spell, body, state) do
    <<spell_id::little-size(32), spell_cast_targets::binary>> = body

    <<spell_cast_target_flags::little-size(16), rest::binary>> = spell_cast_targets

    {unit_target, _rest} =
      cond do
        spell_cast_target_flags == @spell_cast_target_self ->
          {state.guid, rest}

        (spell_cast_target_flags &&& @spell_cast_target_unit) > 0 ->
          unpack_guid(rest)

        true ->
          {nil, rest}
      end

    spell = DBC.get_by(Spell, id: spell_id) |> DBC.preload(:spell_cast_time)
    Logger.info("CMSG_CAST_SPELL: #{spell.name_en_gb} - #{spell_id}", target_name: unit_target)

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

    Registry.dispatch(ThistleTea.PlayerRegistry, state.character.map, fn entries ->
      %{x: x1, y: y1, z: z1} = state.character.movement

      for {pid, values} <- entries do
        {_guid, x2, y2, z2} = values

        if within_range({x1, y1, z1}, {x2, y2, z2}) do
          send(pid, {:send_packet, @smsg_spell_start, spell_start})
        end
      end
    end)

    state =
      Map.put(state, :spell, %{
        spell_id: spell_id,
        target: unit_target,
        spell_cast_targets: spell_cast_targets
      })

    state =
      if spell.spell_cast_time.base == 0 do
        handle_spell_complete(state)
      else
        cast_timer =
          Process.send_after(
            self(),
            :spell_complete,
            spell.spell_cast_time.base
          )

        Map.put(state, :spell, Map.put(state.spell, :cast_timer, cast_timer))
      end

    {:continue, state}
  end

  def handle_packet(@cmsg_cancel_cast, _body, state) do
    Logger.info("CMSG_CANCEL_CAST")
    state = cancel_spell(state)
    {:continue, state}
  end

  def handle_spell_complete(state) do
    s = state.spell
    # TODO: verify orientation, etc.
    cast_result = <<s.spell_id::little-size(32), 0::little-size(8)>>
    send_packet(@smsg_cast_result, cast_result)

    spell_go_flags = 0x100

    spell_go =
      state.packed_guid <>
        state.packed_guid <>
        <<
          s.spell_id::little-size(32),
          # flags
          spell_go_flags::little-size(16),
          # number of hits
          1::little-size(8),
          # guid
          s.target::little-size(64),
          # miss
          0
        >> <>
        s.spell_cast_targets

    Registry.dispatch(ThistleTea.PlayerRegistry, state.character.map, fn entries ->
      %{x: x1, y: y1, z: z1} = state.character.movement

      for {pid, values} <- entries do
        {_guid, x2, y2, z2} = values

        if within_range({x1, y1, z1}, {x2, y2, z2}) do
          send(pid, {:send_packet, @smsg_spell_go, spell_go})
        end
      end
    end)

    Map.delete(state, :spell)
  end
end
