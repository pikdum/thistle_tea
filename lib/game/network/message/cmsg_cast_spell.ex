defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  import Bitwise, only: [&&&: 2]
  import ThistleTea.Util, only: [unpack_guid: 1]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Util

  require Logger

  @spell_cast_target_self 0x00000000
  @spell_cast_target_unit 0x00000002

  defstruct [:spell_id, :spell_cast_targets]

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id, spell_cast_targets: spell_cast_targets}, state) do
    <<spell_cast_target_flags::little-size(16), rest::binary>> = spell_cast_targets

    unit_target =
      cond do
        spell_cast_target_flags == @spell_cast_target_self ->
          state.guid

        (spell_cast_target_flags &&& @spell_cast_target_unit) > 0 ->
          {target, _} = unpack_guid(rest)
          target

        true ->
          nil
      end

    spell = DBC.get_by(Spell, id: spell_id) |> DBC.preload(:spell_cast_time)
    Logger.info("CMSG_CAST_SPELL: #{spell.name_en_gb} - #{spell_id}", target_name: unit_target)

    state = Message.CmsgCancelCast.cancel_spell(state)

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
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<spell_id::little-size(32), spell_cast_targets::binary>> = payload

    %__MODULE__{
      spell_id: spell_id,
      spell_cast_targets: spell_cast_targets
    }
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
