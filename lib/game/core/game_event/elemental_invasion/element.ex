defmodule ThistleTea.Game.Core.GameEvent.ElementalInvasion.Element do
  @moduledoc false

  @enforce_keys [:name, :rift_event, :boss_event, :rift, :invader, :stage_variable, :kills_variable]
  defstruct @enforce_keys
end
