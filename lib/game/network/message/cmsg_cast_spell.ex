defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time

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
    character =
      character
      |> SpellBT.complete_cast(Time.now())
      |> EventSink.emit_pending()

    state
    |> Map.put(:character, character)
    |> Map.delete(:spell)
    |> ensure_player_tick_for_auras()
  end

  def handle_spell_complete(state), do: state

  @simple_spell_cast_result_failure 2
  @cast_failure_reason_more_powerful_spell_active 0x07

  def cast_spell(state, %Spell{} = spell, spell_cast_targets, cast_item_guid \\ nil) do
    targets = Targets.parse(spell_cast_targets, state.guid)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name} - #{spell.id}",
      target_name: targets.unit_guid
    )

    if targets.unit_guid == state.guid and AuraLogic.blocked_by_stronger_rank?(state.character, spell) do
      fail_cast(spell)
      state
    else
      do_cast_spell(state, spell, spell_cast_targets, targets, cast_item_guid)
    end
  end

  defp fail_cast(%Spell{id: spell_id}) do
    Network.send_packet(%Message.SmsgCastResult{
      spell: spell_id,
      result: @simple_spell_cast_result_failure,
      reason: @cast_failure_reason_more_powerful_spell_active,
      required_spell_focus: nil,
      area: nil,
      equipped_item_class: nil,
      equipped_item_subclass_mask: nil,
      equipped_item_inventory_type_mask: nil
    })
  end

  defp do_cast_spell(state, %Spell{} = spell, spell_cast_targets, targets, cast_item_guid) do
    state = Message.CmsgCancelCast.cancel_spell(state)

    cast_item =
      if cast_item_guid, do: BinaryUtils.pack_guid(cast_item_guid), else: state.packed_guid

    %Message.SmsgSpellStart{
      cast_item: cast_item,
      caster: state.packed_guid,
      spell: spell.id,
      flags: 0x2,
      timer: spell.cast_time_ms,
      targets: spell_cast_targets,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(state.character)

    character = SpellBT.start_cast(state.character, spell, targets, Time.now(), cast_item_guid)
    state = Map.put(state, :character, character)

    cond do
      Spell.attribute?(spell, :on_next_swing) -> ensure_player_tick(state)
      spell.cast_time_ms == 0 and not Spell.attribute?(spell, :channeled) -> handle_spell_complete(state)
      true -> ensure_player_tick(state)
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

  defp ensure_player_tick_for_auras(%{character: %{unit: %Unit{auras: [_ | _]}}} = state) do
    ensure_player_tick(state)
  end

  defp ensure_player_tick_for_auras(state), do: state

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
