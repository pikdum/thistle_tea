defmodule ThistleTea.Game.Core.Honor.Participant do
  @moduledoc false
  @enforce_keys [:guid, :team]
  defstruct [:guid, :team, :group_id, alive?: false, in_range?: false]
end
