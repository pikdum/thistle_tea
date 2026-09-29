defmodule ThistleTea.Game.Core.Death.ResurrectionOffer do
  @moduledoc "A single spell resurrection offer and its acknowledged arrival."

  defstruct [:caster_guid, :position, :orientation, :health, :mana, :arrival, phase: :offered]
end
