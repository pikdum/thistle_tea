defmodule ThistleTea.Game.Network.Message.CmsgUseItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_USE_ITEM

  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  require Logger

  @spelltrigger_on_use 0
  @invtype_non_equip 0

  defstruct [:bag, :slot, :spell_count, :targets]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{} = c} = state) do
    pos = {message.bag, message.slot}
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- Inventory.item_guid_at(c.player, pos, get_item),
         %DataItem{} = item <- ItemStore.get(guid),
         template = DataItem.template(item),
         :ok <- validate_usable(c, template, pos),
         {:ok, spell_id, consumable?} <- on_use_spell(template),
         %Spell{} = spell <- SpellLoader.load(spell_id) do
      Logger.info("CMSG_USE_ITEM: #{template.name} casting #{spell.name}")

      state
      |> Spellcasting.cast(spell, message.targets, guid)
      |> maybe_consume(item, pos, consumable?)
    else
      {:error, error} ->
        InventoryUpdate.send_failure(error, Inventory.item_guid_at(c.player, pos, get_item) || 0, 0)
        state

      _ ->
        InventoryUpdate.send_failure(:item_not_found, 0, 0)
        state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<bag, slot, spell_count, targets::binary>> = payload

    %__MODULE__{
      bag: bag,
      slot: slot,
      spell_count: spell_count,
      targets: targets
    }
  end

  defp validate_usable(%Character{unit: unit}, %ItemTemplate{} = template, {bag, slot}) do
    if template.inventory_type != @invtype_non_equip and
         not (bag == Inventory.bag_0() and Inventory.equipment_slot?(slot)) do
      {:error, :item_not_found}
    else
      Inventory.can_use(unit, template)
    end
  end

  defp on_use_spell(%ItemTemplate{} = template) do
    Enum.find_value(1..5, {:error, :item_not_found}, fn i ->
      spell_id = Map.get(template, :"spellid_#{i}")
      trigger = Map.get(template, :"spelltrigger_#{i}")
      charges = Map.get(template, :"spellcharges_#{i}")

      if is_integer(spell_id) and spell_id > 0 and trigger == @spelltrigger_on_use do
        {:ok, spell_id, is_integer(charges) and charges < 0}
      end
    end)
  end

  defp maybe_consume(state, _item, _pos, false), do: state

  defp maybe_consume(%{character: c} = state, %DataItem{} = item, pos, true) do
    get_item = &ItemStore.get/1

    if (item.item.stack_count || 1) > 1 do
      case Inventory.reduce_stack(c.player, pos, 1, get_item) do
        {:ok, result} -> InventoryUpdate.apply(state, {:ok, result})
        _ -> state
      end
    else
      case Inventory.destroy(c.player, pos, get_item) do
        {:ok, result, _item} ->
          ItemStore.delete(item.object.guid)
          Network.send_packet(%Message.SmsgDestroyObject{guid: item.object.guid})
          InventoryUpdate.apply(state, {:ok, result})

        _ ->
          state
      end
    end
  end
end
