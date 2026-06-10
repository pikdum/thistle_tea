defmodule ThistleTea.Game.Entity.Logic.Equipment do
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Item

  @slots [
    head: 1,
    neck: 2,
    shoulders: 3,
    body: 4,
    chest: 5,
    waist: 6,
    legs: 7,
    feet: 8,
    wrists: 9,
    hands: 10,
    finger1: 11,
    finger2: 12,
    trinket1: 13,
    trinket2: 14,
    back: 15,
    mainhand: 16,
    offhand: 17,
    ranged: 18,
    tabard: 19
  ]

  @visible_entry_fields Map.new(@slots, fn {slot, index} -> {slot, String.to_atom("visible_item_#{index}_0")} end)

  def slots, do: Keyword.keys(@slots)

  def visible_entry_field(slot), do: Map.fetch!(@visible_entry_fields, slot)

  def visible_entry(%Player{} = player, slot) do
    Map.get(player, visible_entry_field(slot))
  end

  def equip(%Player{} = player, slot, %Item{object: %Object{guid: guid, entry: entry}}) do
    player
    |> Map.put(slot, guid)
    |> Map.put(visible_entry_field(slot), entry)
  end

  def clear(%Player{} = player, slot) do
    Map.put(player, slot, nil)
  end

  def equipped_guids(%Player{} = player) do
    @slots
    |> Enum.map(fn {slot, _index} -> Map.get(player, slot) end)
    |> Enum.filter(fn guid -> is_integer(guid) and guid > 0 end)
  end
end
