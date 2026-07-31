defmodule ThistleTea.Game.Entity.Data.Reputation do
  @moduledoc false

  defstruct states: %{}, ranks: %{}, temporary_at_war: MapSet.new()
end

defmodule ThistleTea.Game.Entity.Data.Reputation.Catalog do
  @moduledoc false

  defstruct factions: %{}, spillovers: %{}, kill_rewards: %{}, rates: %{}
end

defmodule ThistleTea.Game.Entity.Data.Reputation.Definition do
  @moduledoc false

  defstruct [:id, :index, :name, :parent_faction_id, variants: []]
end

defmodule ThistleTea.Game.Entity.Data.Reputation.Variant do
  @moduledoc false

  defstruct race_mask: 0, class_mask: 0, base_standing: 0, flags: 0
end

defmodule ThistleTea.Game.Entity.Data.Reputation.State do
  @moduledoc false

  defstruct [:faction_id, :index, standing: 0, flags: 0]
end

defmodule ThistleTea.Game.Entity.Data.Reputation.Change do
  @moduledoc false

  defstruct [:faction_id, :index, :standing, :flags]
end

defmodule ThistleTea.Game.Entity.Data.Reputation.Spillover do
  @moduledoc false

  defstruct [:faction_id, :rate, :max_rank]
end

defmodule ThistleTea.Game.Entity.Data.Reputation.KillReward do
  @moduledoc false

  defstruct [:faction_id, :value, :max_rank, :team, team_award?: false]
end
