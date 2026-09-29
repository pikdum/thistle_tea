defmodule ThistleTea.Game.World.Entity.Mob.Incarnation do
  @moduledoc """
  Assigns a unique identity to each live incarnation of a mob spawn.
  """
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Mob

  def ensure(%Mob{internal: %Internal{spawn: %Spawn{incarnation_id: id}}} = state) when is_integer(id) and id > 0 do
    state
  end

  def ensure(%Mob{} = state), do: renew(state)

  def renew(%Mob{internal: %Internal{spawn: %Spawn{} = spawn} = internal} = state) do
    spawn = %{spawn | incarnation_id: System.unique_integer([:positive, :monotonic])}
    %{state | internal: %{internal | spawn: spawn}}
  end

  def renew(%Mob{} = state), do: state

  def id(%Mob{internal: %Internal{spawn: %Spawn{incarnation_id: id}}}) when is_integer(id) and id > 0 do
    id
  end

  def id(%Mob{}), do: nil
end
