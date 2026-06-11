defmodule ThistleTea.Game.Network.Message.CmsgCastSpell do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CAST_SPELL

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Metadata

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

  def cast_spell(state, %Spell{} = spell, spell_cast_targets, cast_item_guid \\ nil) do
    targets = Targets.parse(spell_cast_targets, state.guid)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name} - #{spell.id}",
      target_name: targets.unit_guid
    )

    case validate_cast(state, spell, targets) do
      :ok ->
        do_cast_spell(state, spell, spell_cast_targets, targets, cast_item_guid)

      {:error, reason} ->
        fail_cast(spell, reason)
        state
    end
  end

  defp validate_cast(%{character: character} = state, %Spell{} = spell, %Targets{} = targets) do
    CastValidation.validate(
      character,
      spell,
      targets,
      build_target_info(state, targets),
      Time.now(),
      count_item: fn item_id -> Inventory.count_entry(character.player, item_id, &ItemStore.get/1) end
    )
  end

  defp build_target_info(%{guid: caster_guid}, %Targets{unit_guid: caster_guid}) when is_integer(caster_guid) do
    :self
  end

  defp build_target_info(%{character: character}, %Targets{unit_guid: guid}) when is_integer(guid) and guid > 0 do
    case Metadata.query(guid, [:alive?, :faction_template, :unit_flags]) do
      nil ->
        :unknown

      metadata ->
        %{
          guid: guid,
          alive?: Map.get(metadata, :alive?, true),
          hostile?: Hostility.hostile?(character, metadata),
          friendly?: Hostility.friendly?(character, metadata),
          attackable?: Hostility.attackable?(character, guid),
          position: World.position(guid)
        }
    end
  end

  defp build_target_info(_state, _targets), do: nil

  defp fail_cast(%Spell{id: spell_id}, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
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
    Network.send_packet(Message.SmsgCastResult.failure(spell_id, :not_known))
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
