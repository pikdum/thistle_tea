defmodule ThistleTea.Game.Network.Message.CmsgReadItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_READ_ITEM

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.World.ItemStore

  defstruct [:bag, :slot]

  @impl ClientMessage
  def handle(%__MODULE__{bag: bag, slot: slot}, %{ready: true, character: %Character{} = c} = state) do
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- Inventory.item_guid_at(c.player, {bag, slot}, get_item),
         %Item{} = item <- get_item.(guid),
         template = Item.template(item),
         true <- is_integer(template.page_text) and template.page_text > 0 do
      respond(c, template, guid)
    else
      _not_readable -> InventoryUpdate.send_failure(:item_not_found, 0, 0)
    end

    state
  end

  def handle(_message, state), do: state

  defp respond(c, template, guid) do
    case Inventory.can_use(c.unit, Proficiency.from_character(c), template) do
      :ok ->
        Network.send_packet(%Message.SmsgReadItemOk{guid: guid})

      {:error, error} ->
        Network.send_packet(%Message.SmsgReadItemFailed{guid: guid})
        InventoryUpdate.send_failure(error, guid, 0)
    end
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot
    }
  end
end
