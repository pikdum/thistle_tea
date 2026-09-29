defmodule ThistleTea.Game.Core.Honor.Entry do
  @moduledoc false
  alias ThistleTea.Game.Core.Honor

  @enforce_keys [:guid, :team, :level]
  defstruct [:guid, :team, :level, honor: %Honor{}]
end
