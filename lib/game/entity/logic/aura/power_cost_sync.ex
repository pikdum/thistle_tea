defmodule ThistleTea.Game.Entity.Logic.Aura.PowerCostSync do
  @moduledoc """
  Projects active school cost modifiers into the owner's seven client cost
  fields, rebuilding both arrays on every aura transition.
  """
  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura

  def sync(%Unit{} = unit) do
    entity = %{unit: unit}

    flat =
      for school <- 0..6, into: <<>> do
        amount = Aura.flat_modifier(entity, :mod_power_cost_school, 1 <<< school)
        <<amount::little-signed-size(32)>>
      end

    percent =
      for school <- 0..6, into: <<>> do
        amount = Aura.flat_modifier(entity, :mod_power_cost_school_pct, 1 <<< school)
        <<amount / 100::little-float-size(32)>>
      end

    %{unit | power_cost_modifier: flat, power_cost_multiplier: percent}
  end
end
