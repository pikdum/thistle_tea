defmodule ThistleTea.Game.World.Inbound.Item do
  @moduledoc "Handles decoded inventory, bank, and item use client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.Item, as: DataItem
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory, as: CoreInventory
  alias ThistleTea.Game.Core.Inventory, as: InventoryLogic
  alias ThistleTea.Game.Core.Item.ItemUse
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Ammunition
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.Containers
  alias ThistleTea.Game.World.Entity.Player.Gifts
  alias ThistleTea.Game.World.Entity.Player.Inventory
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Items
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Outbound

  require Logger

  @invtype_non_equip 0

  def messages do
    [
      Message.CmsgAutobankItem,
      Message.CmsgAutoequipItem,
      Message.CmsgAutoequipItemSlot,
      Message.CmsgAutostoreBagItem,
      Message.CmsgAutostoreBankItem,
      Message.CmsgBuyBankSlot,
      Message.CmsgDestroyitem,
      Message.CmsgOpenItem,
      Message.CmsgReadItem,
      Message.CmsgSetAmmo,
      Message.CmsgSplitItem,
      Message.CmsgSwapInvItem,
      Message.CmsgSwapItem,
      Message.CmsgUseItem,
      Message.CmsgWrapItem
    ]
  end

  def handle(%Message.CmsgAutobankItem{source_bag: bag, source_slot: slot}, state),
    do: Bank.auto_bank(state, {bag, slot})

  def handle(
        %Message.CmsgAutoequipItem{src_bag: src_bag, src_slot: src_slot},
        %{ready: true, character: %Character{}} = state
      ) do
    Inventory.auto_equip(state, {src_bag, src_slot})
  end

  def handle(%Message.CmsgAutoequipItem{}, state), do: state

  def handle(
        %Message.CmsgAutoequipItemSlot{item_guid: guid, destination_slot: slot},
        %{ready: true, character: %Character{}} = state
      ) do
    Inventory.equip_item(state, guid, slot)
  end

  def handle(%Message.CmsgAutoequipItemSlot{}, state), do: state

  def handle(%Message.CmsgAutostoreBagItem{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.auto_store_in_bag(state, {message.source_bag, message.source_slot}, message.destination_bag)
  end

  def handle(%Message.CmsgAutostoreBagItem{}, state), do: state

  def handle(%Message.CmsgAutostoreBankItem{source_bag: bag, source_slot: slot}, state),
    do: Bank.auto_store_bank(state, {bag, slot})

  def handle(%Message.CmsgBuyBankSlot{banker_guid: banker_guid}, state), do: Bank.buy_slot(state, banker_guid)

  def handle(%Message.CmsgDestroyitem{bag: bag, slot: slot}, %{ready: true, character: %Character{}} = state) do
    Inventory.destroy(state, {bag, slot})
  end

  def handle(%Message.CmsgDestroyitem{}, state), do: state

  def handle(%Message.CmsgOpenItem{bag: bag, slot: slot}, %{ready: true} = state),
    do: Containers.open(state, {bag, slot})

  def handle(%Message.CmsgOpenItem{}, state), do: state

  def handle(%Message.CmsgReadItem{bag: bag, slot: slot}, %{ready: true, character: %Character{} = c} = state) do
    position = {bag, slot}

    case Bank.authorize_positions(state, [position]) do
      {:ok, state} -> read_item(state, c, position)
      {:error, state} -> cmsg_read_item_reject_remote_bank(state)
    end
  end

  def handle(%Message.CmsgReadItem{}, state), do: state

  def handle(%Message.CmsgSetAmmo{item: item}, %{ready: true, character: %Character{}} = state),
    do: Ammunition.select(state, item)

  def handle(%Message.CmsgSetAmmo{}, state), do: state

  def handle(%Message.CmsgSplitItem{count: count} = message, %{ready: true, character: %Character{}} = state)
      when count > 0 do
    src_pos = {message.src_bag, message.src_slot}
    dst_pos = {message.dst_bag, message.dst_slot}
    Inventory.split(state, src_pos, dst_pos, count)
  end

  def handle(%Message.CmsgSplitItem{}, state), do: state

  def handle(
        %Message.CmsgSwapInvItem{src_slot: src_slot, dst_slot: dst_slot},
        %{ready: true, character: %Character{}} = state
      ) do
    bag_0 = InventoryLogic.bag_0()
    Inventory.swap(state, {bag_0, src_slot}, {bag_0, dst_slot})
  end

  def handle(%Message.CmsgSwapInvItem{}, state), do: state

  def handle(%Message.CmsgSwapItem{} = message, %{ready: true, character: %Character{}} = state) do
    Inventory.swap(state, {message.src_bag, message.src_slot}, {message.dst_bag, message.dst_slot})
  end

  def handle(%Message.CmsgSwapItem{}, state), do: state

  def handle(%Message.CmsgUseItem{} = message, %{ready: true, character: %Character{}} = state) do
    use_item(message, state, &SpellLoader.load/1)
  end

  def handle(%Message.CmsgUseItem{}, state), do: state

  def handle(%Message.CmsgWrapItem{} = message, state) do
    Gifts.wrap(state, {message.gift_bag, message.gift_slot}, {message.item_bag, message.item_slot})
  end

  def use_item(%Message.CmsgUseItem{} = message, %{ready: true, character: %Character{} = c} = state, load_spell)
      when is_function(load_spell, 1) do
    pos = {message.bag, message.slot}

    case Bank.authorize_positions(state, [pos]) do
      {:ok, state} -> use_item_at(message, state, c, pos, load_spell)
      {:error, state} -> cmsg_use_item_reject_remote_bank(state)
    end
  end

  defp read_item(state, c, position) do
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- CoreInventory.item_guid_at(c.player, position, get_item),
         %Item{} = item <- get_item.(guid),
         template = Item.template(item),
         true <- is_integer(template.page_text) and template.page_text > 0 do
      respond(c, template, guid)
    else
      _not_readable -> InventoryUpdate.send_failure(:item_not_found, 0, 0)
    end

    state
  end

  defp cmsg_read_item_reject_remote_bank(state) do
    InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
    state
  end

  defp respond(c, template, guid) do
    case CoreInventory.can_use(c.unit, Proficiency.from_character(c), template, c.player) do
      :ok ->
        Outbound.send_packet(%Message.SmsgReadItemOk{guid: guid})

      {:error, error} ->
        Outbound.send_packet(%Message.SmsgReadItemFailed{guid: guid})
        InventoryUpdate.send_failure(error, guid, 0)
    end
  end

  defp use_item_at(message, state, c, pos, load_spell) do
    get_item = &ItemStore.get/1

    with guid when is_integer(guid) <- CoreInventory.item_guid_at(c.player, pos, get_item),
         %DataItem{} = item <- ItemStore.get(guid),
         template = DataItem.template(item),
         :ok <- validate_usable(c, template, pos),
         {:ok, spell_id, spell_index, consumable?} <- ItemUse.on_use_spell(item),
         %Spell{} = spell <- load_spell.(spell_id) do
      spell = apply_item_cooldowns(spell, template, spell_index)

      Logger.info("CMSG_USE_ITEM: #{template.name} casting #{spell.name}")

      case Spellcasting.cast_result(state, spell, message.targets, guid) do
        {:ok, state} ->
          handle_consumption(state, guid, consumable? and not ItemUse.deferred_costs?(spell, guid))

        {:error, state} ->
          Outbound.send_packet(%Message.SmsgInventoryChangeFailure{})
          state
      end
    else
      {:cast_error, spell_id, reason} ->
        Outbound.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
        state

      {:error, error} ->
        InventoryUpdate.send_failure(error, CoreInventory.item_guid_at(c.player, pos, get_item) || 0, 0)
        state

      _ ->
        InventoryUpdate.send_failure(:item_not_found, 0, 0)
        state
    end
  end

  defp cmsg_use_item_reject_remote_bank(state) do
    InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
    state
  end

  defp validate_usable(%Character{unit: unit} = character, %ItemTemplate{} = template, {bag, slot}) do
    if template.inventory_type != @invtype_non_equip and
         not (bag == CoreInventory.bag_0() and CoreInventory.equipment_slot?(slot)) do
      {:error, :item_not_found}
    else
      with :ok <- CoreInventory.can_use(unit, Proficiency.from_character(character), template, character.player) do
        Reputation.validate_item_requirement(character, template)
      end
    end
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
      Items.consume_cast_item(state, item_guid)
    end
  end

  defp handle_consumption(state, item_guid, true), do: Items.consume_cast_item(state, item_guid)

  defp defer_consumption?(%Cast{cast_time_ms: cast_time_ms} = casting) do
    is_integer(cast_time_ms) and cast_time_ms > 0 and not Cast.channeled?(casting)
  end
end
