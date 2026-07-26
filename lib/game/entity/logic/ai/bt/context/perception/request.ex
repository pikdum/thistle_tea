defmodule ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Request do
  @moduledoc false

  defstruct actors: [], radius: 0.0

  def actor(guid) when is_integer(guid), do: %__MODULE__{actors: [guid]}

  def new(actors \\ [], radius \\ 0.0)

  def new(actors, radius) when is_list(actors) and is_number(radius) and radius >= 0 do
    %__MODULE__{actors: actors, radius: radius}
  end
end
