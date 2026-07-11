defmodule ThistleTea.Game.World.SpawnPool.Member do
  @moduledoc false

  defstruct [:kind, :id, chance: 0.0, flags: 0]

  def key(%__MODULE__{kind: kind, id: id}) when kind in [:creature, :game_object], do: {kind, id}
  def key(%__MODULE__{kind: :pool, id: id}), do: {:pool, id}
end
