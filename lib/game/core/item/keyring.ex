defmodule ThistleTea.Game.Core.Item.Keyring do
  @moduledoc """
  The keyring: inventory slots 81 and up that only hold key-family items.
  Its usable size grows with level the way the 1.12 client draws it, four
  slots below 40, eight from 40, twelve from 50, and sixteen past 60, so
  the server never places a key in a slot the client hides.
  """
  alias ThistleTea.Game.Core.Entity.ItemTemplate

  @bag_family_keys 9
  @first_slot 81
  @max_slots 16

  def first_slot, do: @first_slot
  def max_slots, do: @max_slots

  def size(level) when is_integer(level) and level > 60, do: 16
  def size(level) when is_integer(level) and level >= 50, do: 12
  def size(level) when is_integer(level) and level >= 40, do: 8
  def size(_level), do: 4

  def slot?(slot), do: is_integer(slot) and slot >= @first_slot and slot < @first_slot + @max_slots

  def key?(%ItemTemplate{bag_family: @bag_family_keys}), do: true
  def key?(_template), do: false
end
