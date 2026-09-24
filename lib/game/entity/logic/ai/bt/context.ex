defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context do
  @moduledoc """
  Immutable environment supplied by an entity owner for one behavior-tree
  tick.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Waypoints

  @enforce_keys [
    :now,
    :perception,
    :random,
    :navigation,
    :waypoints,
    :script_conditions,
    :script_conditions_by_target,
    :script_targets,
    :condition_now
  ]
  defstruct [
    :now,
    :perception,
    :random,
    :navigation,
    :waypoints,
    :script_conditions,
    :script_conditions_by_target,
    :script_targets,
    :condition_now,
    :condition_area,
    :liquid_surface,
    :body_height,
    :instance_data,
    :formation,
    :shared_leash_time,
    aura_contexts: %{},
    creature_archetypes: %{}
  ]

  def new(now, opts \\ []) when is_integer(now) do
    %__MODULE__{
      now: now,
      perception: Keyword.get(opts, :perception, Perception.empty(now)),
      random: Keyword.get(opts, :random, Random.fixed()),
      navigation: Keyword.get(opts, :navigation, Navigation.direct()),
      waypoints: Keyword.get(opts, :waypoints, Waypoints.empty()),
      script_conditions: Keyword.get(opts, :script_conditions, %{}),
      script_conditions_by_target: Keyword.get(opts, :script_conditions_by_target, %{}),
      script_targets: Keyword.get(opts, :script_targets, %{}),
      condition_now: Keyword.get(opts, :condition_now),
      condition_area: Keyword.get(opts, :condition_area),
      liquid_surface: Keyword.get(opts, :liquid_surface),
      body_height: Keyword.get(opts, :body_height, 2.0),
      instance_data: Keyword.get(opts, :instance_data),
      formation: Keyword.get(opts, :formation),
      shared_leash_time: Keyword.get(opts, :shared_leash_time),
      aura_contexts: Keyword.get(opts, :aura_contexts, %{}),
      creature_archetypes: Keyword.get(opts, :creature_archetypes, %{})
    }
  end
end
