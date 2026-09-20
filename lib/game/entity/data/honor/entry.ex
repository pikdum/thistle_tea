defmodule ThistleTea.Game.Entity.Data.Honor.Entry do
  @moduledoc false
  alias ThistleTea.Game.Entity.Data.Honor

  @enforce_keys [:guid, :team, :level]
  defstruct [:guid, :team, :level, honor: %Honor{}]
end
