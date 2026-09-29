defmodule ThistleTea.Game.World.Entity.Player.ItemTransformation do
  @moduledoc """
  Revalidates and atomically replaces an owned casting item, then restores
  enchantment expiry delivery for the replacement instance.
  """

  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Item.ItemTransformation, as: Transformation
  alias ThistleTea.Game.Core.Item.ItemUse
  alias ThistleTea.Game.Core.Item.Proficiency
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Enchantments
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Outbound

  def complete(%State{guid: owner, character: character} = state, guid, %Spell{id: spell_id} = spell, entry) do
    with %Item{item: %{owner: ^owner}} = original <- ItemStore.get(guid),
         {:ok, ^spell_id, _index, _commit?} <- ItemUse.on_use_spell(original),
         true <- Enum.any?(spell.effects, &(&1.type == :summon_change_item and &1.misc_value == entry)),
         %ItemTemplate{} = template <- ItemLoader.get_template(entry),
         replacement = template |> ItemStore.prepare(owner: owner) |> Transformation.prepare(original, Time.now()),
         batch = plan_batch(character.player, spell, guid, replacement),
         {:ok, changes} <-
           Inventory.plan(batch, &ItemStore.get/1,
             unit: character.unit,
             proficiency: Proficiency.from_character(character),
             validate_item: &Reputation.validate_item_requirement(character, &1)
           ) do
      state = InventoryUpdate.apply(state, {:ok, changes})
      Enchantments.schedule_item_expiry(replacement)
      Enchantments.send_active_timers(state.character)
      state
    else
      {:error, reason} -> fail(state, spell_id, reason)
      _ -> fail(state, spell_id, :item_not_found)
    end
  end

  defp plan_batch(player, spell, guid, replacement) do
    Enum.reduce(spell.reagents || [], Batch.new(player), fn {entry, count}, batch ->
      Batch.remove(batch, entry, count)
    end)
    |> Batch.replace(guid, replacement)
  end

  defp fail(state, spell_id, _reason) do
    Outbound.send_packet(%Message.SmsgCastResult{spell: spell_id, result: :failed, reason: :item_not_ready})
    state
  end
end
