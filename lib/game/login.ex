defmodule ThistleTea.Game.Login do
  defmacro __using__(_) do
    quote do
      alias ThistleTea.CharacterStorage
      alias ThistleTea.DBC

      import Binary, only: [reverse: 1]

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
        unit_power_1: %{
          # mana
          size: 1,
          offset: 0x17
        },
        unit_power_2: %{
          # rage
          size: 1,
          offset: 0x18
        },
        unit_power_3: %{
          # focus
          size: 1,
          offset: 0x19
        },
        unit_power_4: %{
          # energy
          size: 1,
          offset: 0x1A
        },
        unit_power_5: %{
          # happiness
          size: 1,
          offset: 0x1B
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
          offset: 0x83
        },
        unit_native_display_id: %{
          size: 1,
          offset: 0x84
        },
        player_features: %{
          # skin, face, hair_style, hair_color
          size: 1,
          offset: 0xC1
        },
        player_xp: %{
          size: 1,
          offset: 0x2CC
        },
        player_next_level_xp: %{
          size: 1,
          offset: 0x2CD
        },
        player_rest_state_experience: %{
          size: 1,
          offset: 0x497
        }
      }

      def mask_blocks_count(fields) do
        max_offset = Enum.max(Enum.map(Map.keys(fields), &Map.get(@field_defs, &1).offset))
        trunc(:math.ceil(max_offset / 32))
      end

      def generate_mask(fields) do
        mask_count = mask_blocks_count(fields)
        mask_size = 32 * mask_count
        mask = <<0::size(mask_size)>>

        mask =
          Enum.reduce(fields, mask, fn {field, value}, acc ->
            field_def = Map.get(@field_defs, field)
            size = field_def.size
            offset = field_def.offset

            <<left::size(mask_size - offset - size), _::size(size), right::size(offset)>> = acc

            <<left::size(mask_size - offset - size), 0xFFFFFF::size(size), right::size(offset)>>
          end)

        reverse(mask)
      end

      def generate_objects(fields) do
        fields
        |> Enum.sort(fn {f1, _}, {f2, _} ->
          Map.get(@field_defs, f1).offset < Map.get(@field_defs, f2).offset
        end)
        |> Enum.map(fn {field, value} ->
          case(field) do
            :object_guid -> <<value::little-size(64)>>
            :object_type -> <<value::little-size(32)>>
            :object_scale_x -> <<value::float-little-size(32)>>
            :unit_health -> <<value::little-size(32)>>
            :unit_power_1 -> <<value::little-size(32)>>
            :unit_power_2 -> <<value::little-size(32)>>
            :unit_power_3 -> <<value::little-size(32)>>
            :unit_power_4 -> <<value::little-size(32)>>
            :unit_power_5 -> <<value::little-size(32)>>
            :unit_max_health -> <<value::little-size(32)>>
            :unit_level -> <<value::little-size(32)>>
            :unit_faction_template -> <<value::little-size(32)>>
            :unit_bytes_0 -> value
            :unit_display_id -> <<value::little-size(32)>>
            :unit_native_display_id -> <<value::little-size(32)>>
            :player_features -> value
            :player_xp -> <<value::little-size(32)>>
            :player_next_level_xp -> <<value::little-size(32)>>
            :player_rest_state_experience -> <<value::little-size(32)>>
            _ -> raise "Unknown field: #{field}"
          end
        end)
        |> Enum.reduce(<<>>, fn x, acc -> acc <> x end)
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
          unit_power_1: 100,
          unit_power_2: 100,
          unit_power_3: 100,
          unit_power_4: 100,
          unit_power_5: 100,
          unit_max_health: 100,
          unit_level: c.level,
          unit_faction_template: 1,
          unit_bytes_0: <<c.race, c.class, c.gender, 1>>,
          unit_display_id: unit_display_id,
          unit_native_display_id: unit_display_id,
          player_features: <<c.skin, c.face, c.hairstyle, c.haircolor>>,
          player_xp: 1,
          player_next_level_xp: 100,
          player_rest_state_experience: 100
        }

        mask_count = mask_blocks_count(fields)
        mask = generate_mask(fields)
        objects = generate_objects(fields)
        Logger.info("[GameServer] Objects: #{inspect(objects, limit: :infinity)}")

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
            mask <>
            objects

        send_packet(@smg_update_object, packet)
        {:noreply, {socket, state}}
      end
    end
  end
end
