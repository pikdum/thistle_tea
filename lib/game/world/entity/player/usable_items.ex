defmodule ThistleTea.Game.World.Entity.Player.UsableItems do
  @moduledoc """
  Using and reading items from the player's bags. Use authorizes bank
  positions, validates the item, casts its on-use spell with the slot's
  cooldown overrides, and consumes charges now or when the cast completes.
  Reading answers with the item's page-text result.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.ItemUse
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Bank
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Items
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Outbound

  require Logger

  @invtype_non_equip 0

  def use(%{character: %Character{} = character} = state, position, targets, load_spell \\ &SpellLoader.load/1)
      when is_function(load_spell, 1) do
    case Bank.authorize_positions(state, [position]) do
      {:ok, state} -> use_at(state, character, position, targets, load_spell)
      {:error, state} -> reject_remote_bank(state)
    end
  end

  def read(%{character: %Character{} = character} = state, position) do
    case Bank.authorize_positions(state, [position]) do
      {:ok, state} -> read_at(state, character, position)
      {:error, state} -> reject_remote_bank(state)
    end
  end

  defp use_at(state, character, position, targets, load_spell) do
    with guid when is_integer(guid) <- Inventory.item_guid_at(character.player, position, &ItemStore.get/1),
         %Item{} = item <- ItemStore.get(guid),
         template = Item.template(item),
         :ok <- validate_usable(character, template, position),
         {:ok, spell_id, spell_index, consumable?} <- ItemUse.on_use_spell(item),
         %Spell{} = spell <- load_spell.(spell_id) do
      spell = ItemUse.with_cooldowns(spell, template, spell_index)

      Logger.info("CMSG_USE_ITEM: #{template.name} casting #{spell.name}")

      case Spellcasting.cast_result(state, spell, targets, guid) do
        {:ok, state} ->
          consume(state, guid, consumable? and not ItemUse.deferred_costs?(spell, guid))

        {:error, state} ->
          Outbound.send_packet(%Message.SmsgInventoryChangeFailure{})
          state
      end
    else
      {:cast_error, spell_id, reason} ->
        Outbound.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
        state

      {:error, error} ->
        InventoryUpdate.send_failure(
          error,
          Inventory.item_guid_at(character.player, position, &ItemStore.get/1) || 0,
          0
        )

        state

      _ ->
        InventoryUpdate.send_failure(:item_not_found, 0, 0)
        state
    end
  end

  defp read_at(state, character, position) do
    with guid when is_integer(guid) <- Inventory.item_guid_at(character.player, position, &ItemStore.get/1),
         %Item{} = item <- ItemStore.get(guid),
         %ItemTemplate{page_text: page_text} = template when is_integer(page_text) and page_text > 0 <-
           Item.template(item) do
      read_result(character, template, guid)
    else
      _not_readable -> InventoryUpdate.send_failure(:item_not_found, 0, 0)
    end

    state
  end

  defp read_result(character, template, guid) do
    case Inventory.can_use(character.unit, Proficiency.from_character(character), template, character.player) do
      :ok ->
        Outbound.send_packet(%Message.SmsgReadItemOk{guid: guid})

      {:error, error} ->
        Outbound.send_packet(%Message.SmsgReadItemFailed{guid: guid})
        InventoryUpdate.send_failure(error, guid, 0)
    end
  end

  defp reject_remote_bank(state) do
    InventoryUpdate.send_failure(:too_far_away_from_bank, 0, 0)
    state
  end

  defp validate_usable(%Character{unit: unit} = character, %ItemTemplate{} = template, {bag, slot}) do
    if template.inventory_type != @invtype_non_equip and
         not (bag == Inventory.bag_0() and Inventory.equipment_slot?(slot)) do
      {:error, :item_not_found}
    else
      with :ok <- Inventory.can_use(unit, Proficiency.from_character(character), template, character.player) do
        Reputation.validate_item_requirement(character, template)
      end
    end
  end

  defp consume(state, _item_guid, false), do: state

  defp consume(
         %{
           character:
             %Character{internal: %Internal{casting: %Cast{cast_item_guid: item_guid} = casting} = internal} = character
         } = state,
         item_guid,
         true
       ) do
    if ItemUse.defer_consumption?(casting) do
      %{state | character: %{character | internal: %{internal | casting: %{casting | consume_item: true}}}}
    else
      Items.consume_cast_item(state, item_guid)
    end
  end

  defp consume(state, item_guid, true), do: Items.consume_cast_item(state, item_guid)
end
