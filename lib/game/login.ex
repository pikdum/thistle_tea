defmodule ThistleTea.Game.Login do
  import ThistleTea.Game.UpdateObject
  import Bitwise, only: [<<<: 2, |||: 2]
  import ThistleTea.Util, only: [pack_guid: 1, send_packet: 2, send_update_packet: 1]
  import ThistleTea.Character, only: [get_update_fields: 1]

  alias ThistleTea.DBC

  require Logger

  @cmsg_player_login 0x03D
  @smsg_login_verify_world 0x236
  @smsg_account_data_times 0x209
  @smsg_set_rest_start 0x21E
  @smsg_bindpointupdate 0x155
  @smsg_tutorial_flags 0x0FD
  @smsg_login_settimespeed 0x042
  @smsg_trigger_cinematic 0x0FA

  # @update_flag_none 0x00
  @update_flag_self 0x01
  # @update_flag_transport 0x02
  # @update_flag_melee_attacking 0x04
  @update_flag_high_guid 0x08
  @update_flag_all 0x10
  @update_flag_living 0x20
  @update_flag_has_position 0x40

  @object_type_player 4

  @update_type_create_object2 3

  def handle_packet(@cmsg_player_login, body, state) do
    <<character_guid::little-size(64)>> = body
    Logger.info("CMSG_PLAYER_LOGIN")

    {:ok, c} = ThistleTea.Character.get_character(state.account.id, character_guid)

    :ets.insert(:guid_name, {character_guid, c.name, "", c.race, c.gender, c.class})

    Logger.metadata(character_name: c.name)

    send_packet(
      @smsg_login_verify_world,
      <<c.map::little-size(32), c.movement.x::little-float-size(32),
        c.movement.y::little-float-size(32), c.movement.z::little-float-size(32),
        c.movement.orientation::little-float-size(32)>>
    )

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

    # SMSG_BINDPOINTUPDATE
    # let's just init it to character's position for now
    send_packet(
      @smsg_bindpointupdate,
      <<c.map::little-size(32), c.movement.x::little-float-size(32),
        c.movement.y::little-float-size(32), c.movement.z::little-float-size(32),
        c.movement.orientation::little-float-size(32), c.map::little-size(32),
        c.area::little-size(32)>>
    )

    # no tutorials
    send_packet(@smsg_tutorial_flags, <<0xFFFFFFFFFFFFFFFF::little-size(256)>>)

    # send initial spells
    # send initial action buttons
    # send initial repuations

    # SMSG_LOGIN_SETTIMESPEED
    # TODO: verify this
    dt = DateTime.utc_now()

    date =
      (dt.year - 100) <<< 24 ||| dt.month <<< 20 ||| (dt.day - 1) <<< 14 |||
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

    mb =
      Map.put(
        c.movement,
        :update_flag,
        @update_flag_self ||| @update_flag_all ||| @update_flag_living |||
          @update_flag_has_position
      )

    fields = get_update_fields(c)
    packet = generate_packet(@update_type_create_object2, @object_type_player, fields, mb)

    # player logged in
    send_update_packet(packet)

    # TODO: maybe this should be in response to a CMSG_SET_ACTIVE_MOVER?
    mb =
      Map.put(
        mb,
        :update_flag,
        @update_flag_high_guid ||| @update_flag_living ||| @update_flag_has_position
      )

    packet = generate_packet(@update_type_create_object2, @object_type_player, fields, mb)

    Registry.dispatch(ThistleTea.PubSub, "logged_in", fn entries ->
      for {pid, spawn_packet} <- entries do
        # send packets to everybody else
        send(pid, {:send_update_packet, packet})
        # spawn them for us
        send_update_packet(spawn_packet)
      end
    end)

    # join
    {:ok, _} = Registry.register(ThistleTea.PubSub, "logged_in", packet)

    new_state =
      Map.merge(state, %{
        guid: character_guid,
        packed_guid: pack_guid(character_guid),
        character: c
      })

    {:continue, new_state}
  end
end
