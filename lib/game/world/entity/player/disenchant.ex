defmodule ThistleTea.Game.World.Entity.Player.Disenchant do
  @moduledoc """
  Completes Disenchant against the exact currently owned item. Loot is rolled
  from preloaded templates and retained with the inventory removal in the
  player's commit. Duplicate or stale completion requests cannot reroll it.
  """
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch
  alias ThistleTea.Game.Core.Loot
  alias ThistleTea.Game.Core.Loot.ItemLoot, as: PendingLoot
  alias ThistleTea.Game.Core.Profession.Disenchant, as: DisenchantLogic
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.ItemLoot
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Outbound

  def owned_item(%Character{} = character, guid) when is_integer(guid) do
    if Inventory.find_position(character.player, guid, &ItemStore.get/1), do: ItemStore.get(guid)
  end

  def owned_item(_character, _guid), do: nil

  def complete(%{character: %Character{} = character} = state, guid, spell_id) do
    item = owned_item(character, guid)

    with :ok <- DisenchantLogic.validate_item(character, item),
         %Loot{} = loot <- LootLoader.generate_disenchant(Item.template(item).disenchant_id),
         false <- Loot.empty?(loot),
         {:ok, changes} <-
           character.player |> Batch.new() |> Batch.remove_item(guid, 1) |> Inventory.plan(&ItemStore.get/1) do
      state = Looting.release(state)
      character = DisenchantLogic.skill_up(state.character, :rand.uniform(100) - 1)
      character = %{character | internal: %{character.internal | item_loot: PendingLoot.new(item, loot)}}
      changes = %{changes | player: %{changes.player | skills: character.player.skills}}

      %{state | character: character}
      |> InventoryUpdate.apply({:ok, changes})
      |> ItemLoot.open()
    else
      {:error, reason} -> fail(state, spell_id, reason)
      _ -> fail(state, spell_id, :try_again)
    end
  end

  defp fail(state, spell_id, reason) do
    Outbound.send_packet(Message.SmsgCastResult.failure(spell_id, reason))
    if reason == :already_open, do: ItemLoot.open(state), else: state
  end
end
