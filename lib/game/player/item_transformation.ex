defmodule ThistleTea.Game.Player.ItemTransformation do
  @moduledoc """
  Revalidates and atomically replaces an owned casting item, then restores
  enchantment expiry delivery for the replacement instance.
  """

  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Inventory.Batch
  alias ThistleTea.Game.Entity.Logic.ItemTransformation, as: Transformation
  alias ThistleTea.Game.Entity.Logic.ItemUse
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Enchantments
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

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
    Network.send_packet(%Message.SmsgCastResult{spell: spell_id, result: :failed, reason: :item_not_ready})
    state
  end
end
