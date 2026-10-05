defmodule ThistleTea.Game.World.Entity.Player.ItemLocationLimits do
  @moduledoc "Revalidates carried item locations after travel, inventory changes, and resurrection."

  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Item.ItemLocationLimits, as: ItemLocationLimitsCore
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.World.Entity.Player.InventoryUpdate
  alias ThistleTea.Game.World.Entity.Player.Looting
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader
  alias ThistleTea.Game.World.Pathfinding

  def restore(%Character{} = character, options \\ []) do
    zone = if relevant?(character, :login), do: zone_id(character, options), else: 0
    changes = ItemLocationLimitsCore.plan(character, zone, :login, &ItemStore.get/1)
    InventoryUpdate.apply(character, changes)
  end

  def reconcile(state, options \\ [])

  def reconcile(%State{ready: true, character: %Character{player: %Player{}} = character} = state, options) do
    key = snapshot(character)
    previous = state.item_location_snapshot

    cond do
      unchanged?(previous, key, options) ->
        state

      not relevant?(character, :online) ->
        %{state | item_location_snapshot: %{key: key, zone: Keyword.get(options, :zone_id)}}

      true ->
        zone = zone_id(character, options)
        {:ok, changes} = ItemLocationLimitsCore.plan(character, zone, :online, &ItemStore.get/1)
        state = %{state | item_location_snapshot: %{key: key, zone: zone}}

        state =
          if changes.destroyed == %{} do
            state
          else
            state
            |> cancel_removed_cast(changes)
            |> InventoryUpdate.apply({:ok, changes})
            |> Looting.close_unavailable()
          end

        %{state | item_location_snapshot: %{key: snapshot(state.character), zone: zone}}
    end
  end

  def reconcile(state, _options), do: state

  def invalidate(%State{} = state), do: %{state | item_location_snapshot: nil}
  def invalidate(state), do: state

  defp relevant?(character, phase) do
    if Death.alive?(character) do
      items =
        if phase == :login,
          do: Inventory.all_owned_items(character.player, &ItemStore.get/1),
          else: Inventory.owned_items(character.player, &ItemStore.get/1)

      Enum.any?(
        items,
        &(&1.item.owner == character.object.guid and ItemLocationLimitsCore.restricted?(Item.template(&1)))
      )
    else
      false
    end
  end

  defp unchanged?(%{key: key, zone: zone}, key, options) do
    case Keyword.get(options, :zone_id) do
      hint when is_integer(hint) and hint >= 0 -> hint == zone
      _unknown -> true
    end
  end

  defp unchanged?(_previous, _key, _options), do: false

  defp snapshot(character),
    do:
      {character.object.guid, character.internal.world, character.internal.area, Death.alive?(character),
       character.player}

  defp zone_id(character, options) do
    case Keyword.get(options, :zone_id) do
      hint when is_integer(hint) and hint >= 0 -> hint
      _unknown -> resolve_zone(character)
    end
  end

  defp resolve_zone(%Character{movement_block: %{position: {x, y, z, _orientation}}} = character) do
    map_id = character.internal.world.map_id

    case Pathfinding.get_zone_and_area(map_id, {x, y, z}) do
      {zone, _area} when is_integer(zone) -> zone
      _unknown -> cached_zone(character, map_id)
    end
  end

  defp resolve_zone(%Character{} = character), do: cached_zone(character, character.internal.world.map_id)

  defp cached_zone(character, map_id) do
    case ExplorationLoader.area(character.internal.area) do
      %{map: ^map_id, parent_area_table: parent, id: id} ->
        if parent > 0, do: parent, else: id

      _unknown ->
        ExplorationLoader.sole_zone(map_id) || 0
    end
  end

  defp cancel_removed_cast(%State{character: %{internal: %{casting: %Cast{cast_item_guid: guid}}}} = state, changes) do
    if Map.has_key?(changes.destroyed, guid), do: Spellcasting.cancel(state), else: state
  end

  defp cancel_removed_cast(state, _changes), do: state
end
