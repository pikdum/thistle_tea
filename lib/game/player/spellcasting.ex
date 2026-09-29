defmodule ThistleTea.Game.Player.Spellcasting do
  @moduledoc """
  Player-session spellcasting boundary: looks up and validates casts, starts
  them through the spell behavior tree, completes finished casts, and cancels
  in-progress ones — sending the corresponding cast-result packets and
  (re)scheduling the player tick.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Enchantments
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Entity.Logic.MeleeSpell
  alias ThistleTea.Game.Entity.Logic.Mount
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Entity.Logic.WeaponDamage
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Disenchant
  alias ThistleTea.Game.Player.Fishing
  alias ThistleTea.Game.Player.Gathering
  alias ThistleTea.Game.Player.ItemLoot
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.ObjectTarget
  alias ThistleTea.Game.Player.PetTraining
  alias ThistleTea.Game.Player.Projectile
  alias ThistleTea.Game.Player.Teaching
  alias ThistleTea.Game.Player.Trade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Battleground
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Focus
  alias ThistleTea.Game.Spell.LocationTargets
  alias ThistleTea.Game.Spell.Modifiers
  alias ThistleTea.Game.Spell.Stealth
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.Spell.UnitTargets
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemTarget, as: ItemTargetLoader
  alias ThistleTea.Game.World.Loader.MapTemplate, as: MapTemplateLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpellAreas
  alias ThistleTea.Game.World.SpellEnvironment
  alias ThistleTea.Game.World.SpellFocus
  alias ThistleTea.Game.World.SpellLocations
  alias ThistleTea.Game.World.SpellMounts
  alias ThistleTea.Game.World.SpellObjects
  alias ThistleTea.Game.World.SpellRequirements
  alias ThistleTea.Game.World.SpellTargetInfo
  alias ThistleTea.Game.World.SpellUnits
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  require Logger

  @spell_failed_interrupted 0x23

  def charm_cast(%{ready: true, character: %Character{} = character} = state, %Effects.CharmCast{} = effect) do
    with %Possession{kind: :charm} = control <- character.internal.possession,
         true <- control.caster_guid == effect.controller_guid and control.spell_id == effect.control_spell_id,
         true <- control.applied_at == effect.control_applied_at,
         true <- character.unit.target == effect.target_guid and control.command_target in [nil, effect.target_guid],
         nil <- character.internal.casting,
         %Spell{} = spell <- Enum.find(control.spells, &(&1.id == effect.spell_id)),
         true <- Map.has_key?(character.internal.spellbook, spell.id),
         true <- PlayerCharm.controller_active?(control.caster_guid, Metadata.get(control.caster_guid)),
         {world, _, _, _} when world == character.internal.world <- World.position(control.caster_guid) do
      state = snapshot_action_position(state)
      targets = charm_targets(spell, effect.target_guid)

      if validate_cast(state, spell, targets, nil) == :ok,
        do: state |> cast_target(spell, targets, nil) |> cast_state(),
        else: state
    else
      _invalid -> state
    end
  end

  def charm_cast(state, _effect), do: state

  defp charm_targets(spell, guid) do
    position =
      case World.position(guid) do
        {_world, x, y, z} -> {x, y, z}
        _missing -> nil
      end

    SpellTarget.aim_at_unit(spell, guid, position)
  end

  def scripted_cast(state, %CreatureSpell{} = entry, target_guid) do
    case SpellLoader.load(entry.spell_id) do
      %Spell{} = spell -> scripted_cast(state, spell, entry, target_guid)
      nil -> state
    end
  end

  def scripted_cast(
        %{character: %Character{} = character} = state,
        %Spell{} = spell,
        %CreatureSpell{} = entry,
        target_guid
      ) do
    if character.internal.casting == nil or CreatureSpell.flag?(entry, :interrupt_previous) do
      state = if character.internal.casting, do: cancel(state), else: state

      state
      |> snapshot_action_position()
      |> cast_target(spell, Target.unit(target_guid), nil)
      |> cast_state()
    else
      state
    end
  end

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
    state = snapshot_action_position(state)
    targets = TargetCodec.parse(spell_cast_targets, state.guid)

    Logger.info(
      "CMSG_CAST_SPELL: #{spell.name} - #{spell.id}",
      target_name: Target.unit_guid(targets)
    )

    selected = select_aura_rank(state.character, spell, targets, cast_item_guid)
    requested = if selected.id != spell.id, do: spell
    cast_target(state, selected, targets, cast_item_guid, requested)
  end

  defp select_aura_rank(character, spell, targets, nil) do
    guid = Target.unit_guid(targets)

    level =
      if guid == character.object.guid,
        do: character.unit.level,
        else: Map.get(Metadata.get(guid) || %{}, :level)

    SpellLoader.aura_rank(spell, level) || spell
  end

  defp select_aura_rank(_character, spell, _targets, _item), do: spell

  defp cast_target(state, spell, targets, cast_item_guid, requested \\ nil)

  defp cast_target(state, spell, %Target{selection: {:trade_item, slot}}, cast_item_guid, _requested) do
    Trade.cast(state, spell, slot, cast_item_guid)
  end

  defp cast_target(state, spell, targets, cast_item_guid, requested) do
    spell = WeaponDamage.prepare_spell(state.character, spell)

    with :ok <- validate_item_target(cast_item_guid, targets),
         :ok <- validate_cast(state, spell, targets, cast_item_guid),
         :ok <- Teaching.validate(state.character, spell, cast_item_guid),
         :ok <- PetTraining.validate(state.character, spell),
         {:ok, state} <- Fishing.prepare_cast(state, spell) do
      {:ok, do_cast(state, spell, targets, cast_item_guid, requested)}
    else
      {:error, reason, state} ->
        fail_cast(state, requested || spell, reason)
        {:error, state}

      {:error, reason} ->
        state = dismiss_mount(state, spell, reason)
        fail_cast(state, requested || spell, reason)
        state = if reason == :already_open, do: state |> Looting.release() |> ItemLoot.open(), else: state
        {:error, state}
    end
  end

  defp dismiss_mount(%{character: character} = state, spell, reason) do
    character = character |> Mount.cast_failed(spell, reason, Time.now()) |> EventSink.emit_pending()
    %{state | character: character}
  end

  defp snapshot_action_position(%{character: %Character{} = character} = state) do
    %{state | character: World.snapshot_position(character)}
  end

  defp snapshot_action_position(state), do: state

  defp cast_state({_result, state}), do: state

  def complete(%{character: character} = state) do
    character =
      character
      |> Casting.complete(Time.now())
      |> EventSink.emit_pending()

    state
    |> Map.put(:character, character)
    |> Map.delete(:spell)
    |> TickScheduler.ensure_scheduled()
  end

  def complete(state), do: state

  def cancel_auto_repeat(%{character: %Character{} = character} = state) do
    {character, effects} = AutoRepeat.cancel(character)
    character = EventSink.emit(character, effects)

    state
    |> Map.put(:character, character)
    |> TickScheduler.ensure_scheduled()
  end

  def cancel_auto_repeat(state), do: state

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
          spell: Cast.result_spell(casting).id,
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
        |> World.broadcast_packet(character, include_self?: false)

        character =
          character
          |> Casting.cancel()
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

  defp do_cast(state, %Spell{} = spell, %Target{} = targets, cast_item_guid, requested) do
    state = cancel(state)
    cast_time_ms = Modifiers.integer_value(state.character, spell, :casting_time, spell.cast_time_ms || 0)
    projectile = Projectile.fields(state.character, spell)

    cast_item =
      if cast_item_guid, do: BinaryUtils.pack_guid(cast_item_guid), else: state.packed_guid

    %Message.SmsgSpellStart{
      cast_item: cast_item,
      caster: state.packed_guid,
      spell: spell.id,
      flags: Bitwise.bor(0x2, projectile.flags),
      timer: cast_time_ms,
      targets: targets,
      ammo_display_id: projectile.display_id,
      ammo_inventory_type: projectile.inventory_type
    }
    |> World.broadcast_packet(state.character)

    item_id = cast_item_id(cast_item_guid)

    character =
      Casting.start(state.character, spell, targets, Time.now(), cast_item_guid, item_id,
        requested_spell: requested,
        stealth_roll: stealth_roll(state.character, spell)
      )

    state = %{state | character: character} |> Fishing.start_cast(spell)

    cond do
      Spell.auto_repeat?(spell) -> TickScheduler.schedule_now(state)
      Spell.attribute?(spell, :on_next_swing) -> TickScheduler.schedule_now(state)
      cast_time_ms == 0 and not Spell.attribute?(spell, :channeled) -> complete(state)
      true -> TickScheduler.schedule_now(state)
    end
  end

  defp cast_item_id(guid) when is_integer(guid) do
    case ItemStore.get(guid) do
      %DataItem{object: %{entry: entry}} -> entry
      _ -> 0
    end
  end

  defp cast_item_id(_guid), do: 0

  defp validate_item_target(nil, _targets), do: :ok

  defp validate_item_target(item_guid, %Target{} = targets) do
    requirements = item_guid |> cast_item_id() |> ItemTargetLoader.get()
    guid = Target.unit_guid(targets)
    target = Metadata.get(guid)
    target = if target, do: Map.put(target, :entity_type, Guid.entity_type(guid))
    ItemUse.validate_target(requirements, target)
  end

  defp stealth_roll(character, spell) do
    if Stealth.preservation_chance(character, spell) in 1..99, do: Math.random_int(1, 100)
  end

  def validate_repeat(state, spell, targets), do: validate_cast(state, spell, targets, nil)

  defp validate_cast(%{character: character} = state, %Spell{} = spell, %Target{} = targets, cast_item_guid) do
    enchant_guid = Enchantments.target_guid(character.player, spell, Target.item_guid(targets))
    focus = SpellFocus.find(character, spell)
    locations = SpellLocations.resolve(character, spell, targets, focus)
    targets = LocationTargets.apply(targets, locations)

    with :ok <- Focus.validate(character, spell, focus),
         :ok <- check_party_unit_target(character, spell, targets),
         :ok <- check_object_target(state, spell, targets),
         :ok <- LocationTargets.validate(spell, locations),
         :ok <- UnitTargets.validate(spell, SpellUnits.resolve(character, spell, targets)) do
      CastValidation.validate(
        character,
        spell,
        targets,
        build_target_info(state, spell, targets),
        Time.now(),
        cast_item_guid: cast_item_guid,
        destination_los?: World.line_of_sight?(character, targets.destination_location),
        count_item: fn item_id -> Inventory.count_entry(character.player, item_id, &ItemStore.get/1) end,
        equipped_items: equipped_weapon_templates(character),
        spell_focus: focus,
        spell_objects: SpellObjects.resolve(character, spell, targets, focus, locations),
        spell_corpse: SpellRequirements.corpse(character, spell),
        lock_context: Gathering.context(state, spell, targets, cast_item_guid),
        disenchant_item: Disenchant.owned_item(character, Target.item_guid(targets)),
        enchant_item: Disenchant.owned_item(character, enchant_guid),
        ammo_id: character.player.ammo_id,
        ammo_template: ItemLoader.get_template(character.player.ammo_id),
        mount_context: SpellMounts.context(character, spell),
        battleground: battleground_context(character, spell),
        spell_area: SpellAreas.context(character, spell),
        outdoors?: SpellEnvironment.context(character, spell),
        feed_context: feed_context(character, spell, targets),
        ritual_context: ritual_context(character, spell),
        duel_context: duel_context(character, spell, targets)
      )
    end
  end

  defp check_party_unit_target(character, spell, targets) do
    if SpellTarget.party_member_spell?(spell) do
      validate_party_unit_query(character, SpellTarget.target_query(spell, targets))
    else
      :ok
    end
  end

  defp battleground_context(character, spell) do
    if Battleground.restricted?(spell) do
      ThistleTea.Game.World.System.Battleground.spell_context(character.internal.world, character.object.guid)
    end
  end

  defp check_object_target(state, %Spell{effects: effects, range_yards: range}, targets) do
    if Enum.any?(effects, &(&1.type == :open_lock_item)) do
      case ObjectTarget.resolve(state, Target.object_guid(targets), range) do
        {:ok, _template} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp validate_party_unit_query(character, {:party_unit, _guid} = query) do
    if SpellTargetResolver.resolve_query(character, query) == [], do: {:error, :bad_targets}, else: :ok
  end

  defp validate_party_unit_query(_character, _query), do: {:error, :bad_targets}

  defp ritual_context(
         %Character{object: %{guid: caster_guid}, unit: unit, internal: %{world: caster_world}},
         %Spell{} = spell
       ) do
    if Warlock.ritual_of_summoning?(spell) do
      target_guid = unit.target
      target = Metadata.get(target_guid) || %{}

      %{
        target_player?: Guid.entity_type(target_guid) == :player,
        target_online?: target != %{},
        self?: target_guid == caster_guid,
        same_group?: same_group?(caster_guid, target_guid),
        target_in_combat?: Bitwise.band(Map.get(target, :unit_flags, 0), 0x00080000) != 0,
        caster_dungeon?: MapTemplateLoader.dungeon?(caster_world.map_id),
        caster_battleground?: MapTemplateLoader.battleground?(caster_world.map_id),
        same_world?: match?({^caster_world, _x, _y, _z}, World.position(target_guid))
      }
    end
  end

  defp same_group?(caster_guid, target_guid) do
    case {PartySystem.group_of(caster_guid), PartySystem.group_of(target_guid)} do
      {%{id: id}, %{id: id}} -> true
      _other -> false
    end
  end

  defp feed_context(%Character{} = character, %Spell{effects: effects}, %Target{} = targets) do
    item_guid = Target.item_guid(targets)
    feed_pet? = Enum.any?(effects, &(&1.type == :feed_pet))
    pet_guid = Companion.summon_guid(character)

    if feed_pet? do
      %{item: owned_item_template(character, item_guid), pet: pet_feed_info(pet_guid)}
    end
  end

  defp feed_context(_character, _spell, _targets), do: nil

  defp owned_item_template(%Character{player: player}, item_guid) when is_integer(item_guid) do
    with {_bag, _slot} <- Inventory.find_position(player, item_guid, &ItemStore.get/1),
         %DataItem{} = item <- ItemStore.get(item_guid) do
      DataItem.template(item)
    else
      _ -> nil
    end
  end

  defp owned_item_template(_character, _item_guid), do: nil

  defp pet_feed_info(pet_guid) when is_integer(pet_guid) and pet_guid > 0 do
    case Entity.call(pet_guid, :feed_info) do
      {:ok, info} -> info
      _ -> nil
    end
  end

  defp pet_feed_info(_pet_guid), do: nil

  defp equipped_weapon_templates(%{player: player}) when is_struct(player) do
    [:mainhand, :offhand, :ranged]
    |> Enum.map(&Inventory.equipment_entry(player, &1))
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.map(&ItemLoader.get_template/1)
    |> Enum.reject(&is_nil/1)
  end

  defp equipped_weapon_templates(_character), do: []

  defp build_target_info(%{character: character}, spell, targets),
    do: SpellTargetInfo.resolve(character, spell, targets)

  defp duel_context(
         %Character{object: %{guid: caster_guid}, internal: %{world: caster_world}},
         %Spell{} = spell,
         %Target{} = targets
       ) do
    target_guid = Target.unit_guid(targets)

    if Spell.duel?(spell) and is_integer(target_guid) do
      DuelSystem.challenge_admission(caster_guid, target_guid, caster_world)
    end
  end

  defp duel_context(_character, _spell, _targets), do: nil

  defp fail_cast(state, %Spell{id: spell_id} = spell, reason) do
    Logger.warning("Spell #{spell_id} failed validation: #{reason}")

    if reason == :no_edible_corpses,
      do: Network.send_packet(%Message.SmsgClearCooldown{spell_id: spell_id, target_guid: state.guid})

    Network.send_packet(Message.SmsgCastResult.failure(spell, reason))
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
end
