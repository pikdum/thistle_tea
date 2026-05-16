defmodule ThistleTea.DB.Mangos.PlayerClassLevelStats do
  use Ecto.Schema

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "player_classlevelstats" do
    field(:class, :integer)
    field(:level, :integer)
    field(:base_health, :integer, source: :basehp)
    field(:base_mana, :integer, source: :basemana)
  end

  def get(class, level) do
    Mangos.Repo.get_by(__MODULE__, class: class, level: level)
  end
end
