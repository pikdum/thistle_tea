defmodule ThistleTea.Game.Entity.Data.Component.Internal.Gathering do
  @moduledoc """
  Object-owned lock access, per-spawn skill gains, and harvest count.
  Partial loot retains its contents; each new harvest requires another cast.
  """
  defstruct lock_id: 0,
            min_uses: 1,
            max_uses: 1,
            uses: 0,
            opened_by: %{},
            viewer_monitors: %{},
            skilled_players: MapSet.new()

  def reset(%__MODULE__{} = state),
    do: %{state | uses: 0, opened_by: %{}, viewer_monitors: %{}, skilled_players: MapSet.new()}

  def reset(nil), do: nil
end
