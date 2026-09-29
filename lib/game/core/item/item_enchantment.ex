defmodule ThistleTea.Game.Core.Item.ItemEnchantment do
  @moduledoc false

  defstruct [:id, :name, :item_visual, :flags, effects: [], skill_bonuses: %{}]
end
