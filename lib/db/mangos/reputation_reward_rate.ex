defmodule ThistleTea.DB.Mangos.ReputationRewardRate do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:faction, :integer, autogenerate: false}
  schema "reputation_reward_rate" do
    field(:quest_rate, :float)
    field(:creature_rate, :float)
    field(:spell_rate, :float)
  end
end
