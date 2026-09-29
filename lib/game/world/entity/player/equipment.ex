defmodule ThistleTea.Game.World.Entity.Player.Equipment do
  @moduledoc """
  Resyncs a character's equipment-derived inputs from the item store and
  seed caches: weapon templates, enchantments, set bonuses, and equip spells.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.EquipmentAuras
  alias ThistleTea.Game.Core.Item.EquipmentSets
  alias ThistleTea.Game.Core.Item.EquipmentSpells
  alias ThistleTea.Game.Core.Stats.CombatRatings
  alias ThistleTea.Game.Core.Stats.EquipmentStats
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.ItemEnchantment, as: ItemEnchantmentLoader
  alias ThistleTea.Game.World.Loader.ItemSet, as: ItemSetLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def sync_stats(%Character{} = character) do
    character = %{character | player: Inventory.sync_broken_equipment(character.player, &ItemStore.get/1)}
    now = Time.now()
    enchantments = enchantments(character, now)
    templates = Inventory.equipped_templates(character.player, &ItemStore.get/1)
    set_sources = EquipmentSets.sources(character, templates, &ItemSetLoader.get/1)
    equip_sources = character.player |> Inventory.usable_equipped_items(&ItemStore.get/1) |> EquipmentSpells.sources()

    character
    |> Character.sync_weapon_inputs(weapon_templates(character.player))
    |> EquipmentStats.resync(&ItemStore.get/1, &SpellLoader.load/1, enchantments)
    |> EquipmentAuras.sync(enchantments, &SpellLoader.load/1, now, set_sources ++ equip_sources)
    |> CombatRatings.sync()
  end

  def enchantments(%Character{player: player}, now) do
    for slot <- Inventory.slots(),
        guid = Map.get(player, slot),
        %Item{} = item <- [ItemStore.get(guid)],
        not Item.broken?(item),
        {enchant_slot, id} <- Item.active_enchantments(item, now),
        enchantment = ItemEnchantmentLoader.get(id),
        not is_nil(enchantment),
        do: {slot, item, enchant_slot, enchantment}
  end

  defp weapon_templates(%Player{} = player) do
    %{
      mainhand: equipped_template(player, :mainhand),
      offhand: equipped_template(player, :offhand),
      ranged: equipped_template(player, :ranged),
      ammo: ammo_template(player.ammo_id)
    }
  end

  defp equipped_template(%Player{} = player, slot),
    do: ItemLoader.get_template(Inventory.equipment_entry(player, slot, include_broken: true))

  defp ammo_template(ammo_id) when is_integer(ammo_id) and ammo_id > 0, do: ItemLoader.get_template(ammo_id)
  defp ammo_template(_ammo_id), do: nil
end
