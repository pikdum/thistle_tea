defmodule ThistleTea.Game.Message.CmsgCharEnum do
  use ThistleTea.Game.ClientMessage, :CMSG_CHAR_ENUM

  alias ThistleTea.Game.Message
  alias ThistleTea.Game.Message.SmsgCharEnum.Character
  alias ThistleTea.Game.Message.SmsgCharEnum.CharacterGear
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
        {x, y, z, _o} = c.movement.position

        equipment =
          [
            :head,
            :neck,
            :shoulders,
            :body,
            :chest,
            :waist,
            :legs,
            :feet,
            :wrists,
            :hands,
            :finger1,
            :finger2,
            :trinket1,
            :trinket2,
            :back,
            :mainhand,
            :offhand,
            :ranged,
            :tabard
          ]
          |> Enum.map(fn slot ->
            with equipment when not is_nil(equipment) <- Map.get(c, :equipment),
                 item when not is_nil(item) <- Map.get(equipment, slot) do
              %CharacterGear{
                equipment_display_id: item.display_id,
                inventory_type: item.inventory_type
              }
            else
              _ ->
                %CharacterGear{
                  equipment_display_id: 0,
                  inventory_type: 0
                }
            end
          end)

        %Character{
          guid: c.id,
          name: c.name,
          race: c.race,
          class: c.class,
          gender: c.gender,
          skin: c.skin,
          face: c.face,
          hair_style: c.hair_style,
          hair_color: c.hair_color,
          facial_hair: c.facial_hair,
          level: c.level,
          area: c.area,
          map: c.map,
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
