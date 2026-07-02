defmodule ThistleTea.Game.Network.Message.CmsgUseItem do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_USE_ITEM

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Item, as: DataItem
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Player.Items
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  require Logger

  @spelltrigger_on_use 0
  @invtype_non_equip 0

  defstruct [:bag, :slot, :spell_count, :targets]

  @impl ClientMessage
  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{}} = state) do
    handle(message, state, &SpellLoader.load/1)
  end

  def handle(_message, state), do: state

  def handle(%__MODULE__{} = message, %{ready: true, character: %Character{} = c} = state, load_spell)
      when is_function(load_spell, 1) do
    pos = {message.bag, message.slot}
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- Inventory.item_guid_at(c.player, pos, get_item),
         %DataItem{} = item <- ItemStore.get(guid),
         template = DataItem.template(item),
         :ok <- validate_usable(c, template, pos),
         {:ok, spell_id, spell_index, consumable?} <- on_use_spell(template),
         %Spell{} = spell <- load_spell.(spell_id) do
      spell = apply_item_cooldowns(spell, template, spell_index)

      Logger.info("CMSG_USE_ITEM: #{template.name} casting #{spell.name}")

      case Spellcasting.cast_result(state, spell, message.targets, guid) do
        {:ok, state} -> handle_consumption(state, guid, consumable?)
        {:error, state} -> state
      end
    else
      {:error, error} ->
        InventoryUpdate.send_failure(error, Inventory.item_guid_at(c.player, pos, get_item) || 0, 0)
        state

      _ ->
        InventoryUpdate.send_failure(:item_not_found, 0, 0)
        state
    end
  end

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
        {:ok, spell_id, i, is_integer(charges) and charges < 0}
      end
    end)
  end

  defp apply_item_cooldowns(%Spell{} = spell, %ItemTemplate{} = template, index) do
    spell
    |> maybe_put_positive(:category, Map.get(template, :"spellcategory_#{index}"))
    |> maybe_put_non_negative(:recovery_time_ms, Map.get(template, :"spellcooldown_#{index}"))
    |> maybe_put_non_negative(:category_recovery_time_ms, Map.get(template, :"spellcategorycooldown_#{index}"))
  end

  defp maybe_put_positive(%Spell{} = spell, field, value) when is_integer(value) and value > 0 do
    Map.put(spell, field, value)
  end

  defp maybe_put_positive(%Spell{} = spell, _field, _value), do: spell

  defp maybe_put_non_negative(%Spell{} = spell, field, value) when is_integer(value) and value >= 0 do
    Map.put(spell, field, value)
  end

  defp maybe_put_non_negative(%Spell{} = spell, _field, _value), do: spell

  defp handle_consumption(state, _item_guid, false), do: state

  defp handle_consumption(
         %{
           character:
             %Character{internal: %Internal{casting: %Cast{cast_item_guid: item_guid} = casting} = internal} = c
         } = state,
         item_guid,
         true
       ) do
    if defer_consumption?(casting) do
      casting = %{casting | consume_item: true}
      %{state | character: %{c | internal: %{internal | casting: casting}}}
    else
      Items.consume(state, item_guid)
    end
  end

  defp handle_consumption(state, item_guid, true), do: Items.consume(state, item_guid)

  defp defer_consumption?(%Cast{cast_time_ms: cast_time_ms} = casting) do
    is_integer(cast_time_ms) and cast_time_ms > 0 and not Cast.channeled?(casting)
  end
end
