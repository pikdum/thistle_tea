defmodule ThistleTea.Game.Login do
  import ThistleTea.Game.UpdateObject, only: [get_item_packets: 1]
  import Bitwise, only: [<<<: 2, |||: 2]

  import ThistleTea.Util,
    only: [pack_guid: 1, send_packet: 2, send_update_packet: 1]

  alias ThistleTea.DBC
  alias ThistleTea.Game.Utils.NewUpdateObject

  require Logger

  @cmsg_player_login 0x03D
  @smsg_login_verify_world 0x236
  @smsg_account_data_times 0x209
  @smsg_set_rest_start 0x21E
  @smsg_bindpointupdate 0x155
  @smsg_tutorial_flags 0x0FD
  @smsg_initial_spells 0x12A
  @smsg_login_settimespeed 0x042
  @smsg_trigger_cinematic 0x0FA

  @msg_move_worldport_ack 0x0DC

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

    send_packet(
      @smsg_login_verify_world,
      <<c.map::little-size(32), x::little-float-size(32), y::little-float-size(32),
        z::little-float-size(32), o::little-float-size(32)>>
    )

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
    send_packet(
      @smsg_account_data_times,
      <<0::little-size(128)>>
    )

    # maybe useless? mangos sends it, though
    send_packet(
      @smsg_set_rest_start,
      <<0::little-size(32)>>
    )

    {x, y, z, o} = c.movement.position

    # SMSG_BINDPOINTUPDATE
    # let's just init it to character's position for now
    send_packet(
      @smsg_bindpointupdate,
      <<c.map::little-size(32), x::little-float-size(32), y::little-float-size(32),
        z::little-float-size(32), o::little-float-size(32), c.map::little-size(32),
        c.area::little-size(32)>>
    )

    # no tutorials
    send_packet(@smsg_tutorial_flags, <<0xFFFFFFFFFFFFFFFF::little-size(256)>>)

    # send initial spells
    spells =
      Enum.map(c.spells, &<<&1::little-size(16), 0::little-size(16)>>)
      |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)

    send_packet(
      @smsg_initial_spells,
      <<0, Enum.count(c.spells)::little-size(16)>> <>
        spells <>
        <<0::little-size(16)>>
    )

    # send initial action buttons
    # send initial repuations

    # SMSG_LOGIN_SETTIMESPEED
    # TODO: verify this
    dt = DateTime.utc_now()

    date =
      (dt.year - 80) <<< 24 ||| (dt.month - 1) <<< 20 ||| (dt.day - 1) <<< 14 |||
        Date.day_of_week(dt) <<< 11 ||| dt.hour <<< 6 ||| dt.minute

    send_packet(
      @smsg_login_settimespeed,
      <<date::little-size(32), 0.01666667::little-float-size(32)>>
    )

    chr_race = DBC.get_by(ChrRaces, id: c.race)

    # SMSG_TRIGGER_CINEMATIC
    # TODO: on first login only
    if false do
      send_packet(
        @smsg_trigger_cinematic,
        <<chr_race.cinematic_sequence::little-size(32)>>
      )
    end

    # item packets
    get_item_packets(c.equipment)
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
      |> NewUpdateObject.to_packet()

    send_update_packet(packet)
  end
end
