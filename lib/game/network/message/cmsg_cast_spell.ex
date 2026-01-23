defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Network.Message

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
          {target, _} = BinaryUtils.unpack_guid(rest)
          target

        true ->
          nil
      end

    spell =
      DBC.get_by(Spell, id: spell_id)
      |> DBC.preload(:spell_cast_time)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name_en_gb} - #{spell_id}",
      target_name: unit_target
    )

    state = Message.CmsgCancelCast.cancel_spell(state)

    spell_start_flags = 0x2

    %Message.SmsgSpellStart{
      cast_item: state.packed_guid,
      caster: state.packed_guid,
      spell: spell_id,
      flags: spell_start_flags,
      timer: spell.spell_cast_time.base,
      targets: spell_cast_targets,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(state.character)

    cast_time_ms = spell.spell_cast_time.base || 0

    character =
      SpellBT.start_cast(
        state.character,
        spell_id,
        unit_target,
        spell_cast_targets,
        cast_time_ms
      )

    state = Map.put(state, :character, character)

    if cast_time_ms == 0 do
      handle_spell_complete(state)
    else
      ensure_player_tick(state)
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

  def handle_spell_complete(%{character: character} = state) do
    character = SpellBT.complete_cast(character)

    state
    |> Map.put(:character, character)
    |> Map.delete(:spell)
  end

  def handle_spell_complete(state), do: state

  defp ensure_player_tick(state) do
    case Map.get(state, :player_tick_ref) do
      nil ->
        ref = Process.send_after(self(), :player_tick, 0)
        Map.put(state, :player_tick_ref, ref)

      ref ->
        Process.cancel_timer(ref)
        new_ref = Process.send_after(self(), :player_tick, 0)
        Map.put(state, :player_tick_ref, new_ref)
    end
  end
end
