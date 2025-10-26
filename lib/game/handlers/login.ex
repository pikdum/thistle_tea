defmodule ThistleTea.Game.Login do
  use ThistleTea.Opcodes, [
    :CMSG_PLAYER_LOGIN,
    :SMSG_LOGIN_VERIFY_WORLD,
    :SMSG_ACCOUNT_DATA_TIMES,
    :SMSG_SET_REST_START,
    :SMSG_BINDPOINTUPDATE,
    :SMSG_TUTORIAL_FLAGS,
    :SMSG_INITIAL_SPELLS,
    :SMSG_LOGIN_SETTIMESPEED,
    :SMSG_TRIGGER_CINEMATIC,
    :MSG_MOVE_WORLDPORT_ACK
  ]

  import Bitwise, only: [<<<: 2, |||: 2]

  import ThistleTea.Util,
    only: [pack_guid: 1, send_update_packet: 1]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgInitialSpells.InitialSpell
  alias ThistleTea.Game.Utils.UpdateObject
  alias ThistleTea.Util

  require Logger

  # @update_flag_none 0x00
  @update_flag_self 0x01
  # @update_flag_transport 0x02
  # @update_flag_melee_attacking 0x04
  # @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  def handle_packet(@cmsg_player_login, body, state) do
    <<character_guid::little-size(64)>> = body

    {:ok, c} = ThistleTea.Character.get_character(state.account.id, character_guid)

    :ets.insert(:guid_name, {character_guid, c.name, "", c.race, c.gender, c.class})

    Logger.metadata(character_name: c.name)

    {x, y, z, o} = c.movement.position

    Util.send_packet(%Message.SmsgLoginVerifyWorld{
      map: c.map,
      position: {x, y, z},
      orientation: o
    })

    send_login_init_packets(c)

    {x1, y1, z1, _o1} = c.movement.position

    # join
    SpatialHash.update(:players, character_guid, self(), c.map, x1, y1, z1)

    {:ok, spawn_timer} = :timer.send_interval(1000, :spawn_objects)

    new_state =
      Map.merge(state, %{
        guid: character_guid,
        packed_guid: pack_guid(character_guid),
        character: c,
        spawn_timer: spawn_timer,
        ready: true
      })

    {:continue, new_state}
  end

  def handle_packet(@msg_move_worldport_ack, _body, state) do
    send_login_init_packets(state.character)
    {:continue, state |> Map.put(:ready, true)}
  end

  def send_login_init_packets(c) do
    # needed for no white chatbox + keybinds
    Util.send_packet(%Message.SmsgAccountDataTimes{data: [0, 0, 0, 0]})

    # maybe useless? mangos sends it, though
    Util.send_packet(%Message.SmsgSetRestStart{unknown1: 0})

    {x, y, z, _o} = c.movement.position

    # SMSG_BINDPOINTUPDATE
    # let's just init it to character's position for now
    Util.send_packet(%Message.SmsgBindpointupdate{
      x: x,
      y: y,
      z: z,
      map: c.map,
      area: c.area
    })

    # no tutorials
    Util.send_packet(%Message.SmsgTutorialFlags{
      tutorial_data: [0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF]
    })

    # send initial spells
    spells =
      Enum.map(c.spells, fn spell_id ->
        %InitialSpell{spell_id: spell_id, unknown1: 0}
      end)

    Util.send_packet(%Message.SmsgInitialSpells{
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
        Date.day_of_week(dt) <<< 11 ||| dt.hour <<< 6 ||| dt.minute

    Util.send_packet(%Message.SmsgLoginSettimespeed{
      datetime: date,
      timescale: 0.01666667
    })

    chr_race = DBC.get_by(ChrRaces, id: c.race)

    # SMSG_TRIGGER_CINEMATIC
    # TODO: on first login only
    if false do
      Util.send_packet(%Message.SmsgTriggerCinematic{
        cinematic_sequence_id: chr_race.cinematic_sequence
      })
    end

    # item packets
    UpdateObject.get_item_packets(c.equipment)
    |> Enum.each(fn packet -> send_update_packet(packet) end)

    # packet for player
    update_flag =
      @update_flag_self ||| @update_flag_all ||| @update_flag_living ||| @update_flag_has_position

    packet =
      c
      |> ThistleTea.Character.get_update_fields()
      |> Map.merge(%{
        update_type: :create_object2,
        object_type: :player,
        movement_block: Map.put(c.movement, :update_flag, update_flag)
      })
      |> UpdateObject.to_packet()

    send_update_packet(packet)
  end
end
