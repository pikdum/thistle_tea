defmodule ThistleTea.Game.Network.Message.CmsgPlayerLogin do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PLAYER_LOGIN

  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.Message.SmsgInitialSpells.InitialSpell
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  require Logger

  # @update_flag_none 0x00
  @update_flag_self 0x01
  # @update_flag_transport 0x02
  # @update_flag_melee_attacking 0x04
  # @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  defstruct [:character_guid]

  @impl ClientMessage
  def handle(%__MODULE__{character_guid: character_guid}, state) do
    {:ok, c} = ThistleTea.Character.get_character(state.account.id, character_guid)

    c =
      c
      |> normalize_combat_stats()
      |> normalize_faction_template()
      |> build_spellbook()
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
        alive?: c.unit.health > 0
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

    send_login_init_packets(c)

    {x1, y1, z1, _o1} = c.movement_block.position

    # join
    SpatialHash.update(:players, character_guid, c.internal.map, x1, y1, z1)

    Map.merge(state, %{
      guid: character_guid,
      packed_guid: BinaryUtils.pack_guid(character_guid),
      character: c,
      tracked_entities: MapSet.new(),
      ready: false
    })
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<character_guid::little-size(64)>> = payload

    %__MODULE__{
      character_guid: character_guid
    }
  end

  def send_login_init_packets(c) do
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

    # send initial action buttons
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

    %UpdateObject{
      update_type: :create_object2,
      object_type: :player
    }
    |> struct(Map.from_struct(c))
    |> Map.put(:movement_block, movement_block)
    |> Network.send_packet()
  end

  defp build_spellbook(%ThistleTea.Character{internal: internal} = character) do
    spellbook = SpellLoader.build_spellbook(internal.spells || [])
    %{character | internal: %{internal | spellbook: spellbook}}
  end

  defp normalize_combat_stats(%ThistleTea.Character{} = character) do
    character = ThistleTea.Character.sync_equipment_stats(character)

    unit =
      character.unit
      |> normalize_unit_value(:base_attack_time, 2000)
      |> normalize_unit_value(:bounding_radius, Unit.default_bounding_radius())
      |> normalize_unit_value(:combat_reach, Unit.default_combat_reach())
      |> normalize_unit_value(:min_damage, 2)
      |> normalize_unit_value(:max_damage, 2)

    internal = %{character.internal | in_combat: false}
    %{character | unit: unit, internal: internal}
  end

  defp normalize_faction_template(%ThistleTea.Character{unit: %Unit{race: race} = unit} = character)
       when is_integer(race) do
    case DBC.get_by(ChrRaces, id: race) do
      %ChrRaces{faction: faction_template_id} when is_integer(faction_template_id) and faction_template_id > 0 ->
        %{character | unit: %{unit | faction_template: faction_template_id}}

      _ ->
        character
    end
  end

  defp normalize_faction_template(character), do: character

  defp normalize_unit_value(unit, key, default) do
    case Map.get(unit, key) do
      value when is_number(value) and value > 0 -> unit
      _ -> Map.put(unit, key, default)
    end
  end
end
