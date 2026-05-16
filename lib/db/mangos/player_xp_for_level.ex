defmodule ThistleTea.DB.Mangos.PlayerXpForLevel do
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "player_xp_for_level" do
    field(:level, :integer, source: :lvl)
    field(:xp_for_next_level, :integer)
  end

  def get(level) do
    Mangos.Repo.get_by(__MODULE__, level: level)
  end

  def max_level do
    Mangos.Repo.one(from(x in __MODULE__, select: max(x.level))) || 0
  end
end
