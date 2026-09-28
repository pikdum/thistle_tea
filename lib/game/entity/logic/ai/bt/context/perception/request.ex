defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request do
  @moduledoc false

  alias ThistleTea.Game.Entity.Logic.AI.Script

  defstruct actors: [],
            radius: 0.0,
            game_object_radius: 0.0,
            script_conditions: [],
            script_targets: [],
            random_points: [],
            creature_entries: [],
            combat_zone?: false

  def actor(guid) when is_integer(guid), do: %__MODULE__{actors: [guid]}

  def for_script(steps, actors \\ []) when is_list(steps) and is_list(actors) do
    new(actors, Script.observation_radius(steps),
      game_object_radius: Script.game_object_observation_radius(steps),
      script_conditions: Script.conditions(steps),
      script_targets: Script.target_requests(steps),
      creature_entries: Script.creature_entries(steps),
      random_points: Script.random_point_requests(steps),
      combat_zone?: Script.zone_combat?(steps)
    )
  end

  def new(actors \\ [], radius \\ 0.0, opts \\ [])

  def new(actors, radius, opts) when is_list(actors) and is_number(radius) and radius >= 0 and is_list(opts) do
    game_object_radius = Keyword.get(opts, :game_object_radius, 0.0)
    script_conditions = Keyword.get(opts, :script_conditions, [])
    script_targets = Keyword.get(opts, :script_targets, [])

    %__MODULE__{
      actors: actors,
      radius: radius,
      game_object_radius: game_object_radius,
      script_conditions: script_conditions,
      script_targets: script_targets,
      random_points: Keyword.get(opts, :random_points, []),
      creature_entries: Keyword.get(opts, :creature_entries, []),
      combat_zone?: Keyword.get(opts, :combat_zone?, false)
    }
  end
end
