defmodule ThistleTea.Game.Entity.Logic.AI.Script.Request do
  @moduledoc false

  @enforce_keys [:id, :world, :step, :target_guid, :reply_to, :deadline]
  defstruct @enforce_keys
end
