defmodule ThistleTea.Game.Login do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.CharacterStorage
      alias ThistleTea.DBC

      @cmsg_player_login 0x03D
      @smg_login_verify_world 0x236
      @smg_tutorial_flags 0x0FD
      @smg_update_object 0x0A9
      # @smg_character_login_failed 0x03C

      @impl GenServer
      def handle_cast({:handle_packet, @cmsg_player_login, _size, body}, {socket, state}) do
        <<character_guid::little-size(64)>> = body
        Logger.info("[GameServer] CMSG_PLAYER_LOGIN: character_guid: #{character_guid}")

        c = CharacterStorage.get_by_guid(state.username, character_guid)

        Logger.info("[GameServer] Character: #{inspect(c)}")

        send_packet(
          @smg_login_verify_world,
          <<c.map::little-size(32), c.x::little-float-size(32), c.y::little-float-size(32),
            c.z::little-float-size(32), c.orientation::little-float-size(32)>>
        )

        # no tutorials
        send_packet(@smg_tutorial_flags, <<0xFFFFFFFFFFFFFFFF::little-size(256)>>)

        chr_race = DBC.get_by(ChrRaces, id: c.race)

        unit_display_id =
          case(c.gender) do
            0 -> chr_race.male_display
            1 -> chr_race.female_display
          end

        packet =
          <<
            # block count (1)
            1,
            0,
            0,
            0
          >> <>
            <<
              # has transport
              0
            >> <>
            <<
              # update type = CREATE_NEW_OBJECT2
              3
            >> <>
            <<
              # packet guid, guid = 4
              1,
              4
            >> <>
            <<
              # object type = WO_PLAYER
              4
            >> <>
            <<
              # update flags 0x71
              113
            >> <>
            <<
              # movement flags
              0,
              0,
              0,
              0
            >> <>
            <<
              # timestamp
              0,
              0,
              0,
              0
            >> <>
            <<c.x::little-float-size(32)>> <>
            <<c.y::little-float-size(32)>> <>
            <<c.z::little-float-size(32)>> <>
            <<c.orientation::little-float-size(32)>> <>
            <<
              # fall time
              0,
              0,
              0,
              0
            >> <>
            <<
              # walk speed
              1.0::float-little-size(32)
            >> <>
            <<
              # run speed
              7.0::float-little-size(32)
            >> <>
            <<
              # run back speed
              4.5::float-little-size(32)
            >> <>
            <<
              # swim speed
              0::float-little-size(32)
            >> <>
            <<
              # swim back speed
              0::float-little-size(32)
            >> <>
            <<
              3.1415::float-little-size(32)
            >> <>
            <<
              # is player
              1
            >> <>
            <<
              # unknown hardcoded
              1,
              0,
              0
            >> <>
            <<
              # amount of mask blocks
              5
            >> <>
            <<
              # mask blocks
              23,
              0,
              64,
              16,
              28,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              24,
              0,
              0,
              0
            >> <>
            <<
              # object_field_guid
              4,
              0,
              0,
              0,
              0,
              0,
              0,
              0
            >> <>
            <<
              # object_field_type
              25,
              0,
              0,
              0
            >> <>
            <<
              # scale 1.0
              0,
              0,
              128,
              63
            >> <>
            <<
              # unit_field_health
              100,
              0,
              0,
              0
            >> <>
            <<
              # unit_field_max_health
              100,
              0,
              0,
              0
            >> <>
            <<c.level::little-size(32)>> <>
            <<
              # unit_field_faction_template
              1::little-size(32)
            >> <>
            <<
              c.race,
              c.class,
              c.gender,
              # power (rage)
              1
            >> <>
            <<unit_display_id::little-size(32)>> <>
            <<unit_display_id::little-size(32)>>

        send_packet(@smg_update_object, packet)
        {:noreply, {socket, state}}
      end
    end
  end
end
