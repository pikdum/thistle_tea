defmodule ThistleTea.Game.Core.Item.ItemLocationLimits do
  @moduledoc "Plans removal of map- and zone-bound items while preserving a dead player's inventory."

  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Inventory.Batch

  def restricted?(%ItemTemplate{map: map, area: area}), do: not matches?(map, nil) or not matches?(area, nil)

  def allowed?(%ItemTemplate{map: map, area: area}, map_id, zone_id),
    do: matches?(map, map_id) and matches?(area, zone_id)

  def plan(%Character{} = character, zone_id, phase, get_item) when phase in [:online, :login] do
    batch = Batch.new(character.player)

    if Death.alive?(character) do
      items = owned_items(character, phase, get_item)
      map_id = character.internal.world.map_id
      removed = MapSet.new(Enum.reject(items, &allowed?(Item.template(&1), map_id, zone_id)), & &1.object.guid)

      removed = include_contents(items, removed)

      items
      |> Enum.reverse()
      |> Enum.reduce(batch, &consume_removed(&1, &2, removed))
      |> Inventory.plan(get_item)
    else
      Inventory.plan(batch, get_item)
    end
  end

  defp include_contents(items, removed) do
    Enum.reduce(items, removed, fn item, removed ->
      if MapSet.member?(removed, item.item.contained), do: MapSet.put(removed, item.object.guid), else: removed
    end)
  end

  defp consume_removed(item, batch, removed) do
    if MapSet.member?(removed, item.object.guid),
      do: Batch.consume_item(batch, item.object.guid, item.item.stack_count || 1),
      else: batch
  end

  defp owned_items(character, phase, get_item) do
    items =
      if phase == :login,
        do: Inventory.all_owned_items(character.player, get_item),
        else: Inventory.owned_items(character.player, get_item)

    Enum.filter(items, &(&1.item.owner == character.object.guid))
  end

  defp matches?(binding, location) when is_integer(binding) and binding > 0, do: binding == location
  defp matches?(_binding, _location), do: true
end
