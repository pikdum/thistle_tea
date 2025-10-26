defmodule ThistleTea.Game.Spell do
  use ThistleTea.Opcodes, [
    :CMSG_CAST_SPELL,
    :CMSG_CANCEL_CAST,
    :SMSG_CAST_RESULT,
    :SMSG_SPELL_START,
    :SMSG_SPELL_GO,
    :SMSG_SPELL_FAILURE,
    :SMSG_SPELL_FAILED_OTHER
  ]

  import Bitwise, only: [&&&: 2]
  import ThistleTea.Util, only: [unpack_guid: 1]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Message
  alias ThistleTea.Util

  require Logger

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

        Util.send_packet(%Message.SmsgCastResult{
          spell: spell.spell_id,
          result: 2,
          reason: reason,
          required_spell_focus: nil,
          area: nil,
          equipped_item_class: nil,
          equipped_item_subclass_mask: nil,
          equipped_item_inventory_type_mask: nil
        })

        Util.send_packet(%Message.SmsgSpellFailure{
          guid: state.guid,
          spell: spell.spell_id,
          result: reason
        })

        packet =
          Message.to_packet(%Message.SmsgSpellFailedOther{
            caster: state.guid,
            id: spell.spell_id
          })

        for pid <- Map.get(state, :player_pids, []) do
          if pid != self() do
            GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
          end
        end

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

    packet =
      Message.to_packet(%Message.SmsgSpellStart{
        cast_item: state.packed_guid,
        caster: state.packed_guid,
        spell: spell_id,
        flags: spell_start_flags,
        timer: spell.spell_cast_time.base,
        targets: spell_cast_targets,
        ammo_display_id: nil,
        ammo_inventory_type: nil
      })

    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
    end

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

    Util.send_packet(%Message.SmsgCastResult{
      spell: s.spell_id,
      result: 0,
      reason: nil,
      required_spell_focus: nil,
      area: nil,
      equipped_item_class: nil,
      equipped_item_subclass_mask: nil,
      equipped_item_inventory_type_mask: nil
    })

    spell_go_flags = 0x100

    packet =
      Message.to_packet(%Message.SmsgSpellGo{
        cast_item: state.guid,
        caster: state.guid,
        spell: s.spell_id,
        flags: spell_go_flags,
        hits: [s.target],
        misses: [],
        targets: s.spell_cast_targets,
        ammo_display_id: nil,
        ammo_inventory_type: nil
      })

    if s.target != state.guid do
      pid = :ets.lookup_element(:entities, s.target, 2)
      GenServer.cast(pid, {:receive_spell, state.guid, s.spell_id})
    end

    for pid <- Map.get(state, :player_pids, []) do
      GenServer.cast(pid, {:send_packet, packet.opcode, packet.payload})
    end

    Map.delete(state, :spell)
  end
end
