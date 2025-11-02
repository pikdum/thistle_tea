defmodule ThistleTea.Game.Network.Message.CmsgCharEnum do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CHAR_ENUM

  alias ThistleTea.DB.Mangos.ItemTemplate
  alias ThistleTea.DB.Mangos.Repo
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.SmsgCharEnum.Character
  alias ThistleTea.Game.Network.Message.SmsgCharEnum.CharacterGear
  alias ThistleTea.Util

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_CHAR_ENUM")

    characters = ThistleTea.Character.get_characters!(state.account.id)

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
              item = Repo.get(ItemTemplate, entry)

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
          map: c.internal.map,
          position: {x, y, z},
          guild_id: 0,
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

    Util.send_packet(%Message.SmsgCharEnum{
      amount_of_characters: Enum.count(characters_structs),
      characters: characters_structs
    })

    state
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end
end
