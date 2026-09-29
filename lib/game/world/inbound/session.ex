defmodule ThistleTea.Game.World.Inbound.Session do
  @moduledoc "Handles decoded authentication, character screen, login, and logout client messages."

  alias ThistleTea.Auth.Account
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.ConnectionState
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgCharEnum.Character
  alias ThistleTea.Game.Network.Message.SmsgCharEnum.CharacterGear
  alias ThistleTea.Game.Network.Sessions
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Characters
  alias ThistleTea.Game.World.Entity.Player.Logout
  alias ThistleTea.Game.World.Loader.Character, as: CharacterLoader
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.Guild, as: GuildSystem

  require Logger

  def messages do
    [
      Message.CmsgAuthSession,
      Message.CmsgCharCreate,
      Message.CmsgCharEnum,
      Message.CmsgLogoutCancel,
      Message.CmsgLogoutRequest,
      Message.CmsgPing,
      Message.CmsgPlayerLogin
    ]
  end

  def handle(%Message.CmsgAuthSession{username: username} = message, %{conn: %Connection{} = conn} = state) do
    with {:ok, conn} <- get_session_key(conn, message),
         {:ok, conn} <- verify_proof(conn, message) do
      Outbound.send_packet(%Message.SmsgAuthResponse{
        result: 0x0C,
        billing_time: 0,
        billing_flags: 0,
        billing_rested: 0,
        queue_position: 0
      })

      {:ok, account} = Account.get_user(username)
      :ok = Sessions.authenticate(account.id)

      %{state | conn: conn, account: account}
    else
      _ ->
        Outbound.send_packet(%Message.SmsgAuthResponse{
          result: 0x0D
        })

        state
    end
  end

  def handle(%Message.CmsgCharCreate{} = message, state) do
    Logger.info("CMSG_CHAR_CREATE: #{message.name}")

    character = CharacterLoader.build(message, state.account.id)

    case Characters.create(character) do
      {:error, :character_exists} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x31})

      {:error, :character_limit} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x35})

      {:ok, _} ->
        Outbound.send_packet(%Message.SmsgCharCreate{result: 0x2E})
    end

    state
  end

  def handle(%Message.CmsgCharEnum{}, state) do
    Logger.info("CMSG_CHAR_ENUM")

    characters = CharacterStore.for_account(state.account.id)

    characters_structs =
      characters
      |> Enum.map(fn c ->
        {x, y, z, _o} = c.movement_block.position

        item_entries = [
          c.player.visible_item_1_0,
          c.player.visible_item_2_0,
          c.player.visible_item_3_0,
          c.player.visible_item_4_0,
          c.player.visible_item_5_0,
          c.player.visible_item_6_0,
          c.player.visible_item_7_0,
          c.player.visible_item_8_0,
          c.player.visible_item_9_0,
          c.player.visible_item_10_0,
          c.player.visible_item_11_0,
          c.player.visible_item_12_0,
          c.player.visible_item_13_0,
          c.player.visible_item_14_0,
          c.player.visible_item_15_0,
          c.player.visible_item_16_0,
          c.player.visible_item_17_0,
          c.player.visible_item_18_0,
          c.player.visible_item_19_0
        ]

        equipment =
          item_entries
          |> Enum.map(fn entry ->
            if is_integer(entry) and entry > 0 do
              item = ItemLoader.get_template(Item.visible_entry(entry))

              # credo:disable-for-next-line Credo.Check.Refactor.Nesting
              if item do
                %CharacterGear{
                  equipment_display_id: item.display_id,
                  inventory_type: item.inventory_type
                }
              else
                %CharacterGear{equipment_display_id: 0, inventory_type: 0}
              end
            else
              %CharacterGear{equipment_display_id: 0, inventory_type: 0}
            end
          end)

        %Character{
          guid: c.id,
          name: c.internal.name,
          race: c.unit.race,
          class: c.unit.class,
          gender: c.unit.gender,
          skin: c.player.skin,
          face: c.player.face,
          hair_style: c.player.hair_style,
          hair_color: c.player.hair_color,
          facial_hair: c.player.facial_hair,
          level: c.unit.level,
          area: c.internal.area,
          map: c.internal.world.map_id,
          position: {x, y, z},
          guild_id: guild_id(c.object.guid),
          flags: 0,
          first_login: 0,
          pet_display_id: 0,
          pet_level: 0,
          pet_family: 0,
          equipment: equipment,
          first_bag_display_id: 0,
          first_bag_inventory_type: 0
        }
      end)

    Outbound.send_packet(%Message.SmsgCharEnum{
      amount_of_characters: Enum.count(characters_structs),
      characters: characters_structs
    })

    state
  end

  def handle(%Message.CmsgLogoutCancel{}, state) do
    Logger.info("CMSG_LOGOUT_CANCEL")

    Logout.cancel(state)
  end

  def handle(%Message.CmsgLogoutRequest{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Logout.request(state)
  end

  def handle(%Message.CmsgPing{sequence_id: sequence_id, latency: latency}, %ConnectionState{} = state) do
    Logger.info("CMSG_PING: #{latency}")

    Outbound.send_packet(%Message.SmsgPong{sequence_id: sequence_id})
    %{state | latency: latency}
  end

  def handle(
        %Message.CmsgPlayerLogin{character_guid: character_guid},
        %ConnectionState{account: account, player_pid: nil} = state
      )
      when not is_nil(account) do
    Logger.info("CMSG_PLAYER_LOGIN character_guid=#{character_guid}")

    case PlayerServer.login(account, self(), character_guid) do
      {:ok, player_pid} ->
        ConnectionState.attach_player(state, player_pid)

      {:error, reason} ->
        Logger.error("CMSG_PLAYER_LOGIN failed character_guid=#{character_guid} reason=#{inspect(reason)}")

        Outbound.send_packet(%Message.SmsgCharacterLoginFailed{
          result: Message.SmsgCharacterLoginFailed.result(:failed)
        })

        state
    end
  end

  def handle(%Message.CmsgPlayerLogin{}, state), do: state

  defp get_session_key(%Connection{} = conn, %Message.CmsgAuthSession{username: username}) do
    case :ets.lookup(:session, username) do
      [{^username, session_key}] -> {:ok, %{conn | session_key: session_key}}
      _ -> {:error, conn}
    end
  end

  defp verify_proof(%Connection{seed: seed, session_key: session_key} = conn, %Message.CmsgAuthSession{
         username: username,
         client_seed: client_seed,
         client_proof: client_proof
       }) do
    server_proof =
      :crypto.hash(
        :sha,
        username <> <<0::little-size(32)>> <> client_seed <> seed <> session_key
      )

    if client_proof == server_proof do
      {:ok, conn}
    else
      {:error, :proof_mismatch}
    end
  end

  defp guild_id(guid) do
    case GuildSystem.group_of(guid) do
      %{id: id} -> id
      nil -> 0
    end
  end
end
