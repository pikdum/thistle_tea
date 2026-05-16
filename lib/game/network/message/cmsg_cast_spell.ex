defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets

  require Logger

  defstruct [:spell_id, :spell_cast_targets]

  @impl ClientMessage
  def handle(%__MODULE__{spell_id: spell_id, spell_cast_targets: spell_cast_targets}, state) do
    case lookup_spell(state, spell_id) do
      %Spell{} = spell -> cast_spell(state, spell, spell_cast_targets)
      nil -> handle_unknown_spell(state, spell_id)
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

  defp cast_spell(state, %Spell{} = spell, spell_cast_targets) do
    targets = Targets.parse(spell_cast_targets, state.guid)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name} - #{spell.id}",
      target_name: targets.unit_guid
    )

    state = Message.CmsgCancelCast.cancel_spell(state)

    %Message.SmsgSpellStart{
      cast_item: state.packed_guid,
      caster: state.packed_guid,
      spell: spell.id,
      flags: 0x2,
      timer: spell.cast_time_ms,
      targets: spell_cast_targets,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(state.character)

    character = SpellBT.start_cast(state.character, spell, targets)
    state = Map.put(state, :character, character)

    if spell.cast_time_ms == 0 and not Spell.attribute?(spell, :channeled) do
      handle_spell_complete(state)
    else
      ensure_player_tick(state)
    end
  end

  defp handle_unknown_spell(state, spell_id) do
    Logger.warning("CMSG_CAST_SPELL: spell #{spell_id} not in caster's spellbook")
    state
  end

  defp lookup_spell(%{character: %{internal: %{spellbook: spellbook}}}, spell_id) when is_map(spellbook) do
    Map.get(spellbook, spell_id)
  end

  defp lookup_spell(_state, _spell_id), do: nil

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
