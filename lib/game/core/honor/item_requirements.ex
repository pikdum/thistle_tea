defmodule ThistleTea.Game.Core.Honor.ItemRequirements do
  @moduledoc """
  Vanilla 1.12 item rank requirements: highest earned rank for use, current
  rank and level for purchases. Item templates use internal rank numbers.
  """

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.ItemTemplate

  def can_use?(%Player{} = player, %ItemTemplate{} = template) do
    can_use?(player.highest_honor_rank || 0, template)
  end

  def can_use?(highest_rank, %ItemTemplate{} = template) when is_integer(highest_rank),
    do: highest_rank >= (template.required_honor_rank || 0)

  def can_buy?(%Character{player: player, unit: unit}, %ItemTemplate{} = template) do
    required = template.required_honor_rank || 0

    required <= 0 or
      ((player.honor_rank || 0) >= required and unit.level >= (template.required_level || 0))
  end
end
