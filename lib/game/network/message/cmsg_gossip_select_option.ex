defmodule ThistleTea.Game.Network.Message.CmsgGossipSelectOption do
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GOSSIP_SELECT_OPTION

  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgGossipHello
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Vendor, as: VendorLoader

  defstruct [:guid, :gossip_list_id, :code]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid, gossip_list_id: gossip_list_id}, %{character: %Character{} = c} = state) do
    vendor_option_id = GossipLoader.option_vendor()
    spirit_healer_option_id = GossipLoader.option_spirit_healer()

    state
    |> Map.get(:gossip_menu_options, [])
    |> Enum.find(fn %Option{id: id} -> id == gossip_list_id end)
    |> case do
      nil ->
        state

      %Option{option_id: ^vendor_option_id} ->
        Network.send_packet(%Message.SmsgListInventory{
          vendor_guid: guid,
          items: VendorLoader.items(Guid.entry(guid))
        })

        state

      %Option{option_id: ^spirit_healer_option_id} ->
        if not Death.alive?(c) do
          Network.send_packet(%Message.SmsgSpiritHealerConfirm{guid: guid})
        end

        state

      %Option{action_menu_id: action_menu_id} ->
        case GossipLoader.get_menu(action_menu_id) do
          %Menu{} = menu ->
            CmsgGossipHello.send_menu(guid, menu, CmsgGossipHello.quest_items(guid, c), state)

          nil ->
            state
        end
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), gossip_list_id::little-size(32), rest::binary>> = payload

    %__MODULE__{
      guid: guid,
      gossip_list_id: gossip_list_id,
      code: rest
    }
  end
end
