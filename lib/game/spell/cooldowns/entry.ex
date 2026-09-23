defmodule ThistleTea.Game.Spell.Cooldowns.Entry do
  @moduledoc "A cast's cooldown source, retained item identity, and spell and category deadlines."

  defstruct [:spell, :ready_at, :category_ready_at, :started_at, category: 0, item_id: 0, pending?: false]
end
