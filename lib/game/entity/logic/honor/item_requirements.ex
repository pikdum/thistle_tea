defmodule ThistleTea.Game.Entity.Logic.Honor.ItemRequirements do
  @moduledoc """
  Vanilla 1.12 item rank requirements: highest earned rank for use, current
  rank and level for purchases. Item templates use internal rank numbers.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.ItemTemplate

  def can_use?(%Player{} = player, %ItemTemplate{} = template) do
    (player.highest_honor_rank || 0) >= (template.required_honor_rank || 0)
  end

  def can_buy?(%Character{player: player, unit: unit}, %ItemTemplate{} = template) do
    required = template.required_honor_rank || 0

    required <= 0 or
      ((player.honor_rank || 0) >= required and unit.level >= (template.required_level || 0))
  end
end
