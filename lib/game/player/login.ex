defmodule ThistleTea.Game.Player.Login do
  @moduledoc """
  Player world-entry: loads the character from the store, normalizes
  movement/combat/death state left over from the last session, publishes
  metadata, registers the entity, and sends the login packet sequence.
  `send_init_packets/1` is reused after cross-map teleports.
  """
  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Combat, as: CombatLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgInitialSpells.InitialSpell
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.Player.Spells, as: PlayerSpells
  alias ThistleTea.Game.Player.Stats, as: PlayerStats
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  require Logger

  # @update_flag_none 0x00
  @update_flag_self 0x01
  # @update_flag_transport 0x02
  # @update_flag_melee_attacking 0x04
  # @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  def enter_world(state, character_guid) do
    {:ok, c} = CharacterStore.fetch(state.account.id, character_guid)

    c =
      c
      |> normalize_movement_state()
      |> normalize_combat_stats()
      |> normalize_faction_template()
      |> normalize_death_state(character_guid)
      |> build_spellbook()
      |> Enchantments.restore()
      |> evaluate_login_rest()
      |> BT.init(PlayerBT.tree())

    Metadata.put(
      character_guid,
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
        health_pct: Core.health_pct(c),
        shapeshift_form: c.unit.shapeshift_form
      }
      |> Map.merge(FactionLoader.metadata(c.unit.faction_template))
    )

    Logger.metadata(character_name: c.internal.name)
    Entity.register(character_guid)

    {x, y, z, o} = c.movement_block.position

    Network.send_packet(%Message.SmsgLoginVerifyWorld{
      map: c.internal.map,
      position: {x, y, z},
      orientation: o
    })

    send_init_packets(c)
    Enchantments.send_active_timers(c)

    case PartySystem.group_of(character_guid) do
      %Party.Group{} = group -> Notifier.send_group_list(group)
      _ -> :ok
    end

    {x1, y1, z1, _o1} = c.movement_block.position

    SpatialHash.update(:players, character_guid, c.internal.map, x1, y1, z1)

    state = %{
      state
      | guid: character_guid,
        packed_guid: BinaryUtils.pack_guid(character_guid),
        character: c,
        tracked_entities: MapSet.new(),
        ready: false
    }

    schedule_aura_tick(state)
  end

  def send_init_packets(c) do
    # needed for no white chatbox + keybinds
    Network.send_packet(%Message.SmsgAccountDataTimes{})

    # maybe useless? mangos sends it, though
    Network.send_packet(%Message.SmsgSetRestStart{unknown1: 0})

    {x, y, z, _o} = c.movement_block.position

    # SMSG_BINDPOINTUPDATE
    # let's just init it to character's position for now
    Network.send_packet(%Message.SmsgBindpointupdate{
      x: x,
      y: y,
      z: z,
      map: c.internal.map,
      area: c.internal.area
    })

    # no tutorials
    Network.send_packet(%Message.SmsgTutorialFlags{
      tutorial_data: [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
    })

    # send initial spells
    spells =
      Enum.map(c.internal.spells, fn spell_id ->
        %InitialSpell{spell_id: spell_id, unknown1: 0}
      end)

    Network.send_packet(%Message.SmsgInitialSpells{
      unknown1: 0,
      initial_spells: spells,
      cooldowns: []
    })

    Network.send_packet(%Message.SmsgActionButtons{
      buttons: c.internal.action_buttons || %{}
    })

    PlayerSpells.send_proficiencies(c)

    # send initial repuations

    # SMSG_LOGIN_SETTIMESPEED
    # TODO: verify this
    dt = DateTime.utc_now()

    date =
      (dt.year - 80) <<< 24 ||| (dt.month - 1) <<< 20 ||| (dt.day - 1) <<< 14 |||
        rem(Date.day_of_week(dt), 7) <<< 11 ||| dt.hour <<< 6 ||| dt.minute

    Network.send_packet(%Message.SmsgLoginSettimespeed{
      datetime: date,
      timescale: 0.01666667
    })

    chr_race = DBC.get_by(ChrRaces, id: c.unit.race)

    # SMSG_TRIGGER_CINEMATIC
    # TODO: on first login only
    if false do
      Network.send_packet(%Message.SmsgTriggerCinematic{
        cinematic_sequence_id: chr_race.cinematic_sequence
      })
    end

    item_updates =
      c.player
      |> Inventory.owned_items(&ItemStore.get/1)
      |> Enum.map(&UpdateObject.from_item/1)

    if item_updates != [] do
      Network.send_packet(item_updates)
    end

    # packet for player
    update_flag =
      @update_flag_self ||| @update_flag_all ||| @update_flag_living ||| @update_flag_has_position

    movement_block = %{c.movement_block | update_flag: update_flag}

    update =
      %UpdateObject{
        update_type: :create_object2,
        object_type: :player
      }
      |> struct(Map.from_struct(c))

    %{update | movement_block: movement_block}
    |> Network.send_packet()

    EventSink.emit(c, AuraLogic.self_duration_events(c, Time.now()))
  end

  defp schedule_aura_tick(%{character: %{unit: %Unit{auras: [_ | _]}}} = state) do
    ref = Process.send_after(self(), :player_tick, 0)
    %{state | player_tick_ref: ref}
  end

  defp schedule_aura_tick(state), do: state

  defp build_spellbook(%Character{internal: internal} = character) do
    spellbook = SpellLoader.build_spellbook(internal.spells || [])
    %{character | internal: %{internal | spellbook: spellbook}}
  end

  defp evaluate_login_rest(%Character{} = character) do
    {x, y, z, _o} = character.movement_block.position

    case Pathfinding.get_zone_and_area(character.internal.map, {x, y, z}) do
      {zone, _area} -> PlayerRest.evaluate_zone(character, zone)
      _unknown -> character
    end
  end

  defp normalize_movement_state(%Character{movement_block: movement_block, internal: internal} = character) do
    movement_block =
      %{movement_block | movement_flags: 0, timestamp: 0, fall_time: 0}
      |> Map.merge(MovementBlock.player_speeds())

    MovementStats.recompute(%{
      character
      | movement_block: movement_block,
        internal: %{internal | visibility_cell: nil}
    })
  end

  defp normalize_combat_stats(%Character{} = character) do
    character =
      character
      |> normalize_base_stats()
      |> Character.sync_equipment_stats()

    unit =
      character.unit
      |> normalize_unit_value(:base_attack_time, 2000)
      |> normalize_unit_value(:bounding_radius, Unit.default_bounding_radius())
      |> normalize_unit_value(:combat_reach, Unit.default_combat_reach())
      |> normalize_unit_value(:min_damage, 2)
      |> normalize_unit_value(:max_damage, 2)

    internal = %{character.internal | in_combat: false, threat_refs: nil}

    %{character | unit: unit, internal: internal}
    |> CombatLogic.sync_combat_flag()
  end

  defp normalize_base_stats(%Character{unit: %Unit{} = unit} = character) do
    case PlayerStats.get(unit.race, unit.class, unit.level) do
      {:ok, stats} -> PlayerStats.apply(character, stats)
      _ -> character
    end
  end

  defp normalize_faction_template(%Character{unit: %Unit{race: race} = unit} = character) when is_integer(race) do
    case DBC.get_by(ChrRaces, id: race) do
      %ChrRaces{faction: faction_template_id} when is_integer(faction_template_id) and faction_template_id > 0 ->
        %{character | unit: %{unit | faction_template: faction_template_id}}

      _ ->
        character
    end
  end

  defp normalize_faction_template(character), do: character

  defp normalize_death_state(%Character{} = character, character_guid) do
    if Death.ghost?(character) and is_nil(SpatialHash.get_entity(Corpse.guid_for(character_guid))) do
      {character, _events} = Death.resurrect(character, 0.5, Time.now())
      %{character | internal: %{character.internal | broadcast_update?: false}}
    else
      character
    end
  end

  defp normalize_unit_value(unit, key, default) do
    case Map.get(unit, key) do
      value when is_number(value) and value > 0 -> unit
      _ -> Map.put(unit, key, default)
    end
  end
end
