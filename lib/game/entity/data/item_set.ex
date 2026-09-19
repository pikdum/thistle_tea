defmodule ThistleTea.Game.Entity.Data.ItemSet do
  @moduledoc """
  Equipment set requirements and the spells granted at each piece threshold.
  """

  defstruct [:id, :name, required_skill: 0, required_skill_rank: 0, bonuses: []]
end
