defmodule ThistleTea.Game.Core.Item.ItemProperty do
  @moduledoc "A selected vanilla item property and its permanent enchantment slots."

  defstruct [:id, :suffix, enchantments: []]

  def id(%__MODULE__{id: id}), do: id
  def id(nil), do: 0
end
