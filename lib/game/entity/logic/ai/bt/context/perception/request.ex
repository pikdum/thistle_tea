defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request do
  @moduledoc false

  defstruct actors: [], radius: 0.0, game_object_radius: 0.0, script_conditions: [], script_targets: []

  def actor(guid) when is_integer(guid), do: %__MODULE__{actors: [guid]}

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
      script_targets: script_targets
    }
  end
end
