defmodule ThistleTea.Game.Core.Item.ItemSet do
  @moduledoc """
  Equipment set requirements and the spells granted at each piece threshold.
  """

  defstruct [:id, :name, required_skill: 0, required_skill_rank: 0, bonuses: []]
end
