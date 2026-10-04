defmodule ThistleTea.DB.Mangos.PlayerCritPerAgility do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "player_crit_per_agility" do
    field(:class, :integer)
    field(:level, :integer)
    field(:rate, :float)
  end

  def rate(class, level) do
    Mangos.Repo.one(
      from(r in __MODULE__,
        where: r.class == ^class and r.level <= ^level,
        order_by: [desc: r.level],
        limit: 1,
        select: r.rate
      )
    )
  end
end
