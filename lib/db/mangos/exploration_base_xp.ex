defmodule ThistleTea.DB.Mangos.ExplorationBaseXp do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:level, :integer, autogenerate: false}
  schema "exploration_basexp" do
    field(:base_xp, :integer, source: :basexp)
  end
end
