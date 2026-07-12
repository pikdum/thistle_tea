defmodule ThistleTea.Game.Player.Spellcasting do
  @moduledoc """
  Player-session spellcasting boundary: looks up and validates casts, starts
  them through the spell behavior tree, completes finished casts, and cancels
  in-progress ones — sending the corresponding cast-result packets and
  (re)scheduling the player tick.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.PlayerTick
  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
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

    with :ok <- validate_cast(state, spell, targets),
         {:ok, state} <- Fishing.prepare_cast(state, spell) do
      {:ok, do_cast(state, spell, spell_cast_targets, targets, cast_item_guid)}
    else
      {:error, reason, state} ->
        fail_cast(spell, reason)
        {:error, state}

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

  def cancel_cast_request(state) do
    state
    |> cancel()
    |> clear_next_swing_spell()
  end

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
          |> Fishing.cancel_bobber()
          |> SpellBT.clear_cast()
          |> EventSink.emit_pending()

        state
        |> Map.put(:character, character)
        |> Map.delete(:spell)
    end
  end

  def cancel(state, _reason), do: state

  defp clear_next_swing_spell(%{character: character} = state) do
    case character.internal.next_swing_spell do
      %Spell{} ->
        {character, _spell} = MeleeSpell.consume_next_swing(character)
        %{state | character: character}

      _ ->
        state
    end
  end

  defp clear_next_swing_spell(state), do: state

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
    state = %{state | character: character} |> Fishing.start_cast(spell)

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
      count_item: fn item_id -> Inventory.count_entry(character.player, item_id, &ItemStore.get/1) end,
      equipped_items: equipped_weapon_templates(character)
    )
  end

  defp equipped_weapon_templates(%{player: player}) when is_struct(player) do
    [player.visible_item_16_0, player.visible_item_17_0, player.visible_item_18_0]
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.map(&ItemLoader.get_template/1)
    |> Enum.reject(&is_nil/1)
  end

  defp equipped_weapon_templates(_character), do: []

  defp build_target_info(%{guid: caster_guid, character: character}, %Spell{} = spell, %Targets{unit_guid: unit_guid}) do
    explicit_guid = nonself_guid(unit_guid, caster_guid)
    pet_guid = implicit_pet_guid(character, spell)

    fallback_guid =
      if Spell.requires_hostile_target?(spell) do
        nonself_guid(selected_target(character), caster_guid)
      end

    cond do
      is_integer(pet_guid) -> target_info(character, pet_guid)
      is_integer(explicit_guid) -> target_info(character, explicit_guid)
      is_integer(fallback_guid) -> target_info(character, fallback_guid)
      unit_guid == caster_guid -> :self
      true -> nil
    end
  end

  defp build_target_info(_state, _spell, _targets), do: nil

  defp implicit_pet_guid(%Character{unit: %Unit{summon: pet_guid}}, %Spell{effects: effects})
       when is_integer(pet_guid) and pet_guid > 0 do
    if Enum.any?(effects, &(&1.implicit_target_a == :pet or &1.implicit_target_b == :pet)), do: pet_guid
  end

  defp implicit_pet_guid(_character, _spell), do: nil

  defp target_info(character, guid) do
    case Metadata.query(guid, [
           :alive?,
           :faction_template,
           :unit_flags,
           :health_pct,
           :orientation,
           :creature_type,
           :aura_sources
         ]) do
      nil ->
        :unknown

      metadata ->
        %{
          guid: guid,
          alive?: Map.get(metadata, :alive?, true),
          hostile?: Hostility.hostile?(character, metadata),
          friendly?: Hostility.friendly?(character, metadata),
          attackable?: Hostility.attackable?(character, guid),
          health_pct: Map.get(metadata, :health_pct),
          creature_type: Map.get(metadata, :creature_type),
          position: World.position(guid),
          orientation: Map.get(metadata, :orientation),
          aura_sources: Map.get(metadata, :aura_sources, MapSet.new()),
          los?: World.line_of_sight?(character, guid)
        }
    end
  end

  defp nonself_guid(guid, caster_guid) when is_integer(guid) and guid > 0 and guid != caster_guid, do: guid
  defp nonself_guid(_guid, _caster_guid), do: nil

  defp selected_target(%{unit: %Unit{target: target}}), do: target
  defp selected_target(_character), do: nil

  defp fail_cast(%Spell{id: spell_id} = spell, :equipped_item_class) do
    failure = %{
      Message.SmsgCastResult.failure(spell_id, :equipped_item_class)
      | equipped_item_class: spell.equipped_item_class,
        equipped_item_subclass_mask: spell.equipped_item_subclass_mask,
        equipped_item_inventory_type_mask: 0
    }

    Network.send_packet(failure)
  end

  defp fail_cast(%Spell{id: spell_id}, reason) do
    Logger.warning("Spell #{spell_id} failed validation: #{reason}")
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
