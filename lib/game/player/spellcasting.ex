defmodule ThistleTea.Game.Player.Spellcasting do
  @moduledoc """
  Player-session spellcasting boundary: looks up and validates casts, starts
  them through the spell behavior tree, completes finished casts, and cancels
  in-progress ones — sending the corresponding cast-result packets and
  (re)scheduling the player tick.
  """
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.PlayerTick
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Metadata

  require Logger

  @spell_failed_interrupted 0x23

  def cast(state, spell_id, spell_cast_targets) when is_integer(spell_id) do
    state
    |> cast_result(spell_id, spell_cast_targets)
    |> cast_state()
  end

  def cast(state, %Spell{} = spell, spell_cast_targets), do: cast(state, spell, spell_cast_targets, nil)

  def cast(state, %Spell{} = spell, spell_cast_targets, cast_item_guid) do
    state
    |> cast_result(spell, spell_cast_targets, cast_item_guid)
    |> cast_state()
  end

  def cast_result(state, spell_id, spell_cast_targets) when is_integer(spell_id) do
    case lookup_spell(state, spell_id) do
      %Spell{} = spell -> cast_result(state, spell, spell_cast_targets)
      nil -> {:error, unknown_spell(state, spell_id)}
    end
  end

  def cast_result(state, %Spell{} = spell, spell_cast_targets), do: cast_result(state, spell, spell_cast_targets, nil)

  def cast_result(state, %Spell{} = spell, spell_cast_targets, cast_item_guid) do
    targets = Targets.parse(spell_cast_targets, state.guid)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name} - #{spell.id}",
      target_name: targets.unit_guid
    )

    case validate_cast(state, spell, targets) do
      :ok ->
        {:ok, do_cast(state, spell, spell_cast_targets, targets, cast_item_guid)}

      {:error, reason} ->
        fail_cast(spell, reason)
        {:error, state}
    end
  end

  defp cast_state({_result, state}), do: state

  def complete(%{character: character} = state) do
    character =
      character
      |> SpellBT.complete_cast(Time.now())
      |> EventSink.emit_pending()

    state
    |> Map.put(:character, character)
    |> Map.delete(:spell)
    |> schedule_tick_for_auras()
  end

  def complete(state), do: state

  def cancel(state, reason \\ @spell_failed_interrupted)

  def cancel(%{character: character} = state, reason) do
    case character.internal.casting do
      nil ->
        state

      casting ->
        spell_id = Cast.spell_id(casting)

        Network.send_packet(%Message.SmsgCastResult{
          spell: spell_id,
          result: 2,
          reason: reason,
          required_spell_focus: nil,
          area: nil,
          equipped_item_class: nil,
          equipped_item_subclass_mask: nil,
          equipped_item_inventory_type_mask: nil
        })

        Network.send_packet(%Message.SmsgSpellFailure{
          guid: state.guid,
          spell: spell_id,
          result: reason
        })

        %Message.SmsgSpellFailedOther{
          caster: state.guid,
          id: spell_id
        }
        |> World.broadcast_packet(character, exclude_self?: true)

        character =
          character
          |> SpellBT.clear_cast()
          |> EventSink.emit_pending()

        state
        |> Map.put(:character, character)
        |> Map.delete(:spell)
    end
  end

  def cancel(state, _reason), do: state

  defp do_cast(state, %Spell{} = spell, spell_cast_targets, targets, cast_item_guid) do
    state = cancel(state)

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
    state = %{state | character: character}

    cond do
      Spell.attribute?(spell, :on_next_swing) -> PlayerTick.schedule_now(state)
      spell.cast_time_ms == 0 and not Spell.attribute?(spell, :channeled) -> complete(state)
      true -> PlayerTick.schedule_now(state)
    end
  end

  defp validate_cast(%{character: character} = state, %Spell{} = spell, %Targets{} = targets) do
    CastValidation.validate(
      character,
      spell,
      targets,
      build_target_info(state, spell, targets),
      Time.now(),
      count_item: fn item_id -> Inventory.count_entry(character.player, item_id, &ItemStore.get/1) end
    )
  end

  defp build_target_info(%{guid: caster_guid, character: character}, %Spell{} = spell, %Targets{unit_guid: unit_guid}) do
    explicit_guid = nonself_guid(unit_guid, caster_guid)

    fallback_guid =
      if Spell.requires_hostile_target?(spell) do
        nonself_guid(selected_target(character), caster_guid)
      end

    cond do
      is_integer(explicit_guid) -> target_info(character, explicit_guid)
      is_integer(fallback_guid) -> target_info(character, fallback_guid)
      unit_guid == caster_guid -> :self
      true -> nil
    end
  end

  defp build_target_info(_state, _spell, _targets), do: nil

  defp target_info(character, guid) do
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

  defp nonself_guid(guid, caster_guid) when is_integer(guid) and guid > 0 and guid != caster_guid, do: guid
  defp nonself_guid(_guid, _caster_guid), do: nil

  defp selected_target(%{unit: %Unit{target: target}}), do: target
  defp selected_target(_character), do: nil

  defp fail_cast(%Spell{id: spell_id}, reason) do
    Network.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
  end

  defp unknown_spell(state, spell_id) do
    Logger.warning("CMSG_CAST_SPELL: spell #{spell_id} not in caster's spellbook")
    Network.send_packet(Message.SmsgCastResult.failure(spell_id, :not_known))
    state
  end

  defp lookup_spell(%{character: %{internal: %{spellbook: spellbook}}}, spell_id) when is_map(spellbook) do
    Map.get(spellbook, spell_id)
  end

  defp lookup_spell(_state, _spell_id), do: nil

  defp schedule_tick_for_auras(%{character: %{unit: %Unit{auras: [_ | _]}}} = state) do
    PlayerTick.schedule_now(state)
  end

  defp schedule_tick_for_auras(state), do: state
end
