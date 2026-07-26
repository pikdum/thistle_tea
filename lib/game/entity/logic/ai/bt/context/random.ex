defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Random do
  @moduledoc """
  Random choices supplied by the entity owner to behavior-tree nodes.
  """

  @enforce_keys [:float, :integer]
  defstruct [:float, :integer]

  def fixed(float \\ 0.5, integer \\ 1)
      when is_number(float) and float >= 0.0 and float < 1.0 and is_integer(integer) and integer > 0 do
    %__MODULE__{
      float: fn -> float / 1 end,
      integer: fn upper -> min(integer, upper) end
    }
  end

  def float(%__MODULE__{float: float}), do: float.()
  def integer(%__MODULE__{integer: integer}, upper) when is_integer(upper) and upper > 0, do: integer.(upper)
end
