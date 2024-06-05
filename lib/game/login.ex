defmodule ThistleTea.Game.Login do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.CharacterStorage
      alias ThistleTea.DBC

      @cmsg_player_login 0x03D
      @smg_login_verify_world 0x236
      @smg_tutorial_flags 0x0FD
      @smg_update_object 0x0A9

      # https://gtker.com/wow_messages/types/update-mask.html
      @field_defs %{
        object_guid: %{
          size: 2,
          offset: 0x0
        },
        object_type: %{
          size: 1,
          offset: 0x2
        },
        object_scale_x: %{
          size: 1,
          offset: 0x4
        },
        unit_health: %{
          size: 1,
          offset: 0x16
        },
        unit_max_health: %{
          size: 1,
          offset: 0x1C
        },
        unit_level: %{
          size: 1,
          offset: 0x22
        },
        unit_faction_template: %{
          size: 1,
          offset: 0x23
        },
        unit_bytes_0: %{
          size: 1,
          offset: 0x24
        },
        unit_display_id: %{
          size: 1,
          offset: 0x98
        },
        unit_native_display_id: %{
          size: 1,
          offset: 0x99
        }
      }

      def mask_blocks_count(fields) do
        max_offset = Enum.max(Enum.map(Map.keys(fields), &Map.get(@field_defs, &1).offset))
        trunc(:math.ceil(max_offset / 32))
      end

      def encode_movement_block(m) do
        {x, y, z, orientation} = m.position

        <<m.update_flag::little-size(8)>> <>
          <<
            m.movement_flags::little-size(32),
            # unknown (timestamp?)
            0::little-size(32),
            # position
            x::little-float-size(32),
            y::little-float-size(32),
            z::little-float-size(32),
            orientation::little-float-size(32)
          >> <>
          <<m.fall_time::little-float-size(32)>> <>
          <<
            # speed block
            m.walk_speed::float-little-size(32),
            m.run_speed::float-little-size(32),
            m.run_back_speed::float-little-size(32),
            m.swim_speed::float-little-size(32),
            m.swim_back_speed::float-little-size(32),
            m.turn_rate::float-little-size(32)
          >>

        # do i need is_player?
        # or unknown hardcoded?
        # looks like yes, but why?
      end

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

        # SMSG_ACCOUNT_DATA_TIMES needed for no white chatbox :)
        # https://gtker.com/wow_messages/docs/smsg_account_data_times.html

        # SMG_SET_REST_START - maybe useless?
        # SMSG_BINDPOINTUPDATE - they send this just before tutorial

        # no tutorials
        send_packet(@smg_tutorial_flags, <<0xFFFFFFFFFFFFFFFF::little-size(256)>>)

        # send initial spells
        # send initial action buttons
        # send initial repuations

        # SMSG_LOGIN_SETTIMESPEED
        # SMSG_TRIGGER_CINEMATIC

        chr_race = DBC.get_by(ChrRaces, id: c.race)

        unit_display_id =
          case(c.gender) do
            0 -> chr_race.male_display
            1 -> chr_race.female_display
          end

        movement_block = %{
          # what is 0x71?
          update_flag: 0x71,
          movement_flags: 0,
          position: {c.x, c.y, c.z, c.orientation},
          fall_time: 0.0,
          walk_speed: 1.0,
          run_speed: 7.0,
          run_back_speed: 4.5,
          swim_speed: 0.0,
          swim_back_speed: 0.0,
          turn_rate: 3.1415
        }

        fields = %{
          object_guid: 4,
          object_type: 25,
          object_scale_x: 1.0,
          unit_health: 100,
          unit_max_health: 100,
          unit_level: c.level,
          unit_faction_template: 1,
          unit_bytes_0: <<c.race, c.class, c.gender, 1>>,
          unit_display_id: unit_display_id,
          unit_native_display_id: unit_display_id
        }

        mask_count = mask_blocks_count(fields)
        Logger.info("[GameServer] Mask count: #{mask_count}")

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
            encode_movement_block(movement_block) <>
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
            <<mask_count>> <>
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
