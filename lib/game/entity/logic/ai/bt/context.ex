defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context do
  @moduledoc """
  Immutable environment supplied by an entity owner for one behavior-tree
  tick.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints

  @enforce_keys [:now, :perception, :random, :navigation, :waypoints]
  defstruct [:now, :perception, :random, :navigation, :waypoints]

  def new(now, opts \\ []) when is_integer(now) do
    %__MODULE__{
      now: now,
      perception: Keyword.get(opts, :perception, Perception.empty(now)),
      random: Keyword.get(opts, :random, Random.fixed()),
      navigation: Keyword.get(opts, :navigation, Navigation.direct()),
      waypoints: Keyword.get(opts, :waypoints, Waypoints.empty())
    }
  end
end
