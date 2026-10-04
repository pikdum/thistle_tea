defmodule ThistleTea.Game.World.Entity.Player.Login do
  @moduledoc """
  Player world-entry: loads the character from the store, normalizes
  movement/combat/death state left over from the last session, publishes
  metadata, registers the entity, and sends the login packet sequence.
  `send_init_packets/1` is reused after cross-map teleports.
  """
  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.DB.DBC
  alias ThistleTea.Game.Core.AI.BT
  alias ThistleTea.Game.Core.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Core.Aura, as: AuraCore
  alias ThistleTea.Game.Core.Aura.DispelResistance
  alias ThistleTea.Game.Core.Aura.ModifierSync
  alias ThistleTea.Game.Core.Aura.SingleTarget
  alias ThistleTea.Game.Core.Aura.StealthDetection
  alias ThistleTea.Game.Core.Chat.ChatStatus
  alias ThistleTea.Game.Core.Chat.Emote
  alias ThistleTea.Game.Core.Combat, as: CombatCore
  alias ThistleTea.Game.Core.Combat.Reactive
  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Duel.Dueling
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Honor.Damage, as: HonorDamage
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Movement.ControlMovement
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Player.Logout
  alias ThistleTea.Game.Core.Player.PlayedTime
  alias ThistleTea.Game.Core.Player.PlayerFlags
  alias ThistleTea.Game.Core.Player.Talents, as: TalentsCore
  alias ThistleTea.Game.Core.Player.Tutorials
  alias ThistleTea.Game.Core.Pvp
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.SpellResist
  alias ThistleTea.Game.Core.Spell.SpellThreat
  alias ThistleTea.Game.Core.Stats.MovementStats
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.Travel.Taxi.Flight
  alias ThistleTea.Game.Core.Travel.Transport, as: TransportCore
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgInitialSpells.CooldownSpell
  alias ThistleTea.Game.Network.Message.SmsgInitialSpells.InitialSpell
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.AccountDataStore
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.Player.AccountCaches
  alias ThistleTea.Game.World.Entity.Player.Auction
  alias ThistleTea.Game.World.Entity.Player.Buyback
  alias ThistleTea.Game.World.Entity.Player.Cinematic, as: PlayerCinematic
  alias ThistleTea.Game.World.Entity.Player.ConditionContext
  alias ThistleTea.Game.World.Entity.Player.Corpses
  alias ThistleTea.Game.World.Entity.Player.Enchantments
  alias ThistleTea.Game.World.Entity.Player.Equipment
  alias ThistleTea.Game.World.Entity.Player.Guilds
  alias ThistleTea.Game.World.Entity.Player.HomeBind
  alias ThistleTea.Game.World.Entity.Player.Honor
  alias ThistleTea.Game.World.Entity.Player.Instances
  alias ThistleTea.Game.World.Entity.Player.ItemDurations
  alias ThistleTea.Game.World.Entity.Player.LiquidSpells
  alias ThistleTea.Game.World.Entity.Player.Mail
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Entity.Player.Reputation, as: PlayerReputation
  alias ThistleTea.Game.World.Entity.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.World.Entity.Player.Social
  alias ThistleTea.Game.World.Entity.Player.SpellEnvironment
  alias ThistleTea.Game.World.Entity.Player.Spells, as: PlayerSpells
  alias ThistleTea.Game.World.Entity.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.World.Entity.Player.TickScheduler
  alias ThistleTea.Game.World.Entity.Player.Trade
  alias ThistleTea.Game.World.Entity.Player.VendorPurchase
  alias ThistleTea.Game.World.Entity.Player.WorldStates
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Talent, as: TalentLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.Party.Notifier

  # @update_flag_none 0x00
  @update_flag_self 0x01
  # @update_flag_transport 0x02
  # @update_flag_melee_attacking 0x04
  # @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  def query_time(%{ready: true, guid: guid} = state) do
    Outbound.send_packet(%Message.SmsgQueryTimeResponse{time: System.system_time(:second)}, guid)
    state
  end

  def query_time(state), do: state

  def played_time(%{ready: true, guid: guid, character: %Character{} = character} = state) do
    {total, level} = PlayedTime.seconds(character, Time.now())
    Outbound.send_packet(%Message.SmsgPlayedTime{total: total, level: level}, guid)
    state
  end

  def played_time(state), do: state

  def mark_tutorial(%{account: %{id: account_id}} = state, index) do
    account_id
    |> AccountDataStore.tutorials()
    |> Tutorials.mark(index)
    |> then(&AccountDataStore.put_tutorials(account_id, &1))

    state
  end

  def mark_tutorial(state, _index), do: state

  def set_tutorials(%{account: %{id: account_id}} = state, :clear) do
    AccountDataStore.put_tutorials(account_id, Tutorials.all_seen())
    state
  end

  def set_tutorials(%{account: %{id: account_id}} = state, :reset) do
    AccountDataStore.put_tutorials(account_id, Tutorials.new())
    state
  end

  def set_tutorials(state, _action), do: state

  def enter_world(state, character_guid) do
    {:ok, c} = CharacterStore.fetch(state.account.id, character_guid)
    intro = if PlayedTime.first_login?(c), do: intro_sequence(c)
    c = c |> Trade.recover() |> Auction.recover() |> VendorPurchase.recover()
    old_item_counts = Quests.quest_item_counts(c)

    c =
      c
      |> Buyback.reset()
      |> ItemDurations.restore()
      |> ChatStatus.reset()
      |> Reactive.clear(Time.now())
      |> Logout.cancel(Time.now())
      |> PlayedTime.start(Time.now())
      |> Emote.reset()
      |> Instances.restore(character_guid)
      |> normalize_movement_state()
      |> normalize_combat_stats()
      |> normalize_faction_template()
      |> normalize_reputation()
      |> Corpses.restore()
      |> Dueling.abandon(Time.now())
      |> Pvp.reconnect(Time.now())
      |> build_spellbook()
      |> SpellEnvironment.restore()
      |> LiquidSpells.restore()
      |> PlayerSpells.apply_passives(Time.now())
      |> PlayerSpells.apply_default_auras(Time.now())
      |> TalentsCore.sync_points(TalentLoader)
      |> Enchantments.restore()
      |> PlayerRest.restore()
      |> evaluate_login_rest()
      |> Honor.sync()
      |> Guilds.attach()
      |> BT.init(PlayerBT.tree())
      |> ControlMovement.restore(Time.now())
      |> ModifierSync.restore()
      |> SingleTarget.detach(Time.now())

    c = PlayerFlags.set_group_leader(c, party_leader?(character_guid))

    Presence.enter(
      c,
      %{
        name: c.internal.name,
        realm: "",
        race: c.unit.race,
        gender: c.unit.gender,
        class: c.unit.class,
        level: c.unit.level,
        bounding_radius: c.unit.bounding_radius,
        combat_reach: c.unit.combat_reach,
        unit_flags: c.unit.flags,
        attacker_count: 0,
        alive?: Death.alive?(c),
        ghost?: Death.ghost?(c),
        in_combat: c.internal.in_combat == true,
        rooted?: c.internal.rooted? == true,
        root_aura?: AuraCore.has_aura?(c, :mod_root),
        health_pct: EntityCore.health_pct(c),
        mana_pct: EntityCore.mana_pct(c),
        shapeshift_form: c.unit.shapeshift_form,
        controlled_guid: Character.controlled_guid(c),
        duel_opponent_guid: Dueling.opponent_guid(c),
        duel_started?: Dueling.active?(c),
        reputation: PlayerReputation.projection(c),
        aura_stacks: AuraCore.spell_stacks(c),
        aura_effects: AuraCore.effect_keys(c),
        crowd_controlled?: AuraCore.crowd_controlled?(c),
        breakable_crowd_control?: AuraCore.breakable_crowd_control?(c),
        mechanic_resistance: AuraCore.misc_amounts(c, :mechanic_resistance),
        school_resistances: SpellResist.school_resistances(c),
        spell_threat: SpellThreat.projection(c),
        dispel_resistance: DispelResistance.projection(c),
        attacker_spell_hit_chance: AuraCore.attacker_spell_hit_chance(c),
        needed_quest_items: Quests.needed_items(c),
        condition_subject: ConditionContext.snapshot(c).target
      }
      |> Map.merge(StealthDetection.target_metadata(c))
      |> Map.merge(FactionLoader.metadata(c.unit.faction_template))
    )

    Logger.metadata(character_name: c.internal.name)
    {c, mail_session_token} = Mail.open_session(c, character_guid)

    {x, y, z, o} = c.movement_block.position

    Outbound.send_packet(%Message.SmsgLoginVerifyWorld{
      map: c.internal.world.map_id,
      position: {x, y, z},
      orientation: o
    })

    send_init_packets(c, intro_cinematic: intro)
    Social.send_lists(c)
    Enchantments.send_active_timers(c)
    Guilds.signed_on(c)

    case PartySystem.group_of(character_guid) do
      %Party.Group{} = group -> Notifier.send_group_list(group)
      _ -> :ok
    end

    state = %{
      state
      | guid: character_guid,
        packed_guid: BinaryUtils.pack_guid(character_guid),
        character: c,
        mail_session_token: mail_session_token,
        tracked_entities: MapSet.new(),
        ready: false
    }

    state
    |> Trade.finish_recovery()
    |> Auction.finish_recovery()
    |> VendorPurchase.finish_recovery()
    |> Quests.on_inventory_changed(old_item_counts)
    |> ItemDurations.start()
    |> TickScheduler.ensure_scheduled()
    |> Mail.schedule_delivery()
    |> Quests.restore_timers()
    |> PlayerCinematic.prepare(intro)
  end

  def restore_companion(%{character: %Character{internal: %Internal{taxi_flight: %Flight{}}}} = state), do: state

  def restore_companion(
        %{character: %Character{internal: %{companion: %Companion{restore_automatically?: false}}}} = state
      ), do: state

  def restore_companion(
        %{
          character:
            %Character{internal: %Internal{companion: %Companion{kind: kind, status: {:suspended, entry, spell_id}}}} =
              character
        } = state
      )
      when kind in [:hunter_pet, :guardian] and is_integer(entry) and entry > 0 and is_integer(spell_id) and
             spell_id > 0 do
    if Death.alive?(character) and not character.internal.companion.dead? do
      EventSink.emit(character, companion_restoration(character, entry, spell_id))
    end

    state
  end

  def restore_companion(
        %{
          character: %Character{
            internal: %Internal{companion: %Companion{kind: kind, status: {:active, %EntityRef{} = ref}}}
          }
        } = state
      )
      when kind in [:hunter_pet, :guardian] do
    case Entity.pid(ref.guid) do
      pid when is_pid(pid) ->
        send(pid, {:attach_pet, self(), ref.spell_id, nil})
        state

      _dead ->
        state = %{state | character: Companion.suspend(state.character)}
        restore_companion(state)
    end
  end

  def restore_companion(
        %{
          character: %Character{internal: %Internal{companion: %Companion{status: {:active, %EntityRef{}}}}} = character
        } = state
      ) do
    %{state | character: Companion.clear(character)}
  end

  def restore_companion(state), do: state

  defp companion_restoration(character, entry, spell_id) do
    case SpellLoader.cached(spell_id) do
      %Spell{effects: effects} ->
        if Enum.any?(effects, &(&1.type == :summon)) do
          %Effects.SummonControlledPet{
            source_guid: character.object.guid,
            entry: entry,
            spell_id: spell_id,
            duration_ms: 0
          }
        else
          Effects.summon_pet(character.object.guid, entry, spell_id)
        end

      _unknown ->
        Effects.summon_pet(character.object.guid, entry, spell_id)
    end
  end

  def refresh_companion(
        %{
          character: %Character{
            internal: %Internal{companion: %Companion{kind: kind, status: {:active, %EntityRef{} = ref}}}
          }
        } = state
      )
      when kind in [:hunter_pet, :guardian] do
    case Entity.pid(ref.guid) do
      pid when is_pid(pid) -> send(pid, {:attach_pet, self(), ref.spell_id, nil})
      _missing -> :ok
    end

    state
  end

  def refresh_companion(state), do: state

  def send_init_packets(c, opts \\ []) do
    Instances.send_saved_instances(c.object.guid)
    WorldStates.initialize(c)
    Corpses.send_reclaim_delay(c)

    # needed for no white chatbox + keybinds
    Outbound.send_packet(AccountCaches.digests(c.account_id, c.object.guid))

    # maybe useless? mangos sends it, though
    Outbound.send_packet(%Message.SmsgSetRestStart{unknown1: 0})

    HomeBind.send_update(c)

    Outbound.send_packet(%Message.SmsgTutorialFlags{tutorial_data: AccountDataStore.tutorials(c.account_id)})

    # send initial spells
    spells =
      Enum.map(c.internal.spells, fn spell_id ->
        %InitialSpell{spell_id: spell_id, unknown1: 0}
      end)

    cooldowns =
      c
      |> Cooldowns.initial(c.internal.spellbook, Time.now())
      |> Enum.map(fn cooldown ->
        %CooldownSpell{
          spell_id: cooldown.spell_id,
          item_id: cooldown.item_id,
          spell_category: cooldown.category,
          cooldown: cooldown.spell_ms,
          category_cooldown: cooldown.category_ms
        }
      end)

    Outbound.send_packet(%Message.SmsgInitialSpells{
      unknown1: 0,
      initial_spells: spells,
      cooldowns: cooldowns
    })

    Outbound.send_packet(%Message.SmsgActionButtons{
      buttons: c.internal.action_buttons || %{}
    })

    PlayerSpells.send_proficiencies(c)

    PlayerReputation.send_initial(c)

    # SMSG_LOGIN_SETTIMESPEED
    dt = DateTime.utc_now()

    date =
      (dt.year - 2000) <<< 24 ||| (dt.month - 1) <<< 20 ||| (dt.day - 1) <<< 14 |||
        rem(Date.day_of_week(dt), 7) <<< 11 ||| dt.hour <<< 6 ||| dt.minute

    Outbound.send_packet(%Message.SmsgLoginSettimespeed{
      datetime: date,
      timescale: 0.01666667
    })

    if sequence = Keyword.get(opts, :intro_cinematic),
      do: Outbound.send_packet(%Message.SmsgTriggerCinematic{cinematic_sequence_id: sequence})

    item_updates = owned_item_updates(c)

    if item_updates != [] do
      Outbound.send_packet(item_updates)
    end

    if Keyword.get(opts, :send_self?, true), do: Outbound.send_packet(self_update(c))

    EventSink.emit(c, AuraCore.self_duration_events(c, Time.now()))
  end

  def send_worldport_packets(%Character{} = character) do
    {character, updates} = worldport_updates(character)
    send_init_packets(character, send_self?: false)
    Outbound.send_packet(updates)
    character
  end

  def worldport_updates(%Character{} = character) do
    case attached_transport_update(character) do
      %UpdateObject{} = transport_update ->
        character = align_to_transport(character, transport_update)
        {character, [transport_update, self_update(character)]}

      nil ->
        {character, [self_update(character)]}
    end
  end

  def self_update(%Character{} = character) do
    update_flag =
      @update_flag_self ||| @update_flag_all ||| @update_flag_living ||| @update_flag_has_position

    movement_block = %{character.movement_block | update_flag: update_flag}

    %UpdateObject{
      update_type: :create_object2,
      object_type: :player
    }
    |> struct(Map.from_struct(character))
    |> then(&%{&1 | movement_block: movement_block})
  end

  def owned_item_updates(%Character{} = character, item_lookup \\ &ItemStore.get/1) do
    character.player
    |> Inventory.all_owned_items(item_lookup)
    |> Enum.map(&UpdateObject.from_item/1)
  end

  defp attached_transport_update(%Character{movement_block: %MovementBlock{transport_guid: guid}})
       when is_integer(guid) do
    case Entity.transport_update(guid) do
      {:ok, %UpdateObject{} = update} -> update
      _error -> nil
    end
  end

  defp attached_transport_update(%Character{}), do: nil

  defp align_to_transport(
         %Character{movement_block: %MovementBlock{transport_position: local_position} = movement_block} = character,
         %UpdateObject{movement_block: %MovementBlock{position: transport_position}}
       )
       when is_tuple(local_position) and is_tuple(transport_position) do
    position = TransportCore.passenger_world_position(local_position, transport_position)
    %{character | movement_block: %{movement_block | position: position, timestamp: 0}}
  end

  defp align_to_transport(%Character{} = character, %UpdateObject{}), do: character

  defp build_spellbook(%Character{internal: internal} = character) do
    spellbook = SpellLoader.build_spellbook(internal.spells || [])
    %{character | internal: %{internal | spellbook: spellbook}}
  end

  defp evaluate_login_rest(%Character{} = character) do
    {x, y, z, _o} = character.movement_block.position

    case Pathfinding.get_zone_and_area(character.internal.world.map_id, {x, y, z}) do
      {zone, _area} -> PlayerRest.evaluate_zone(character, zone)
      _unknown -> PlayerRest.evaluate_zone(character, PlayerRest.default_zone(character.internal.world.map_id))
    end
  end

  defp normalize_movement_state(%Character{movement_block: movement_block, internal: internal} = character) do
    movement_block =
      movement_block
      |> MovementBlock.clear_transport()
      |> then(&%{&1 | movement_flags: 0, timestamp: 0, fall_time: 0})
      |> Map.merge(MovementBlock.player_speeds())

    MovementStats.recompute(%{
      character
      | movement_block: movement_block,
        internal: %{
          internal
          | visibility_cell: nil,
            proximity: nil,
            proximity_refresh: nil,
            hidden_cell: nil,
            breath: nil,
            fatigue: nil,
            lava_exposure: nil,
            honor_damage: %HonorDamage{}
        }
    })
  end

  defp normalize_combat_stats(%Character{} = character) do
    character =
      character
      |> normalize_base_stats()
      |> Equipment.sync_stats()

    unit =
      character.unit
      |> normalize_unit_value(:base_attack_time, 2000)
      |> normalize_unit_value(:bounding_radius, Unit.default_bounding_radius())
      |> normalize_unit_value(:combat_reach, Unit.default_combat_reach())
      |> normalize_unit_value(:min_damage, 2)
      |> normalize_unit_value(:max_damage, 2)

    internal = %{character.internal | in_combat: false, threat_refs: nil}

    %{character | unit: unit, internal: internal}
    |> CombatCore.sync_combat_flag()
  end

  defp normalize_base_stats(%Character{unit: %Unit{} = unit} = character) do
    case PlayerStats.get(unit.race, unit.class, unit.level) do
      {:ok, stats} -> PlayerStats.apply(character, stats)
      _ -> character
    end
  end

  defp normalize_faction_template(%Character{unit: %Unit{race: race} = unit} = character) when is_integer(race) do
    case DBC.get_by(DBC.ChrRaces, id: race) do
      %DBC.ChrRaces{faction: faction_template_id} when is_integer(faction_template_id) and faction_template_id > 0 ->
        %{character | unit: %{unit | faction_template: faction_template_id}}

      _ ->
        character
    end
  end

  defp normalize_faction_template(character), do: character

  defp intro_sequence(%Character{unit: %Unit{race: race}}) do
    case DBC.get_by(DBC.ChrRaces, id: race) do
      %DBC.ChrRaces{cinematic_sequence: sequence} when is_integer(sequence) and sequence > 0 -> sequence
      _ -> nil
    end
  end

  defp normalize_reputation(%Character{unit: unit, player: player} = character) do
    reputation =
      Reputation.normalize(
        player.reputation || %Reputation{},
        ReputationLoader.catalog(),
        unit.race,
        unit.class
      )

    %{character | player: %{player | reputation: reputation}}
  end

  defp party_leader?(guid) do
    case PartySystem.group_of(guid) do
      %Party.Group{leader: ^guid} -> true
      _ -> false
    end
  end

  defp normalize_unit_value(unit, key, default) do
    case Map.get(unit, key) do
      value when is_number(value) and value > 0 -> unit
      _ -> Map.put(unit, key, default)
    end
  end
end
