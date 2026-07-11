defmodule ThistleTea.Game.Entity.Data.ItemEnchantment do
  @moduledoc false

  defstruct [:id, :name, :item_visual, :flags, effects: [], skill_bonuses: %{}]
end
