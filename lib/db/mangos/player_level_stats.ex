defmodule ThistleTea.DB.Mangos.PlayerLevelStats do
  use Ecto.Schema

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "player_levelstats" do
    field(:race, :integer)
    field(:class, :integer)
    field(:level, :integer)
    field(:strength, :integer, source: :str)
    field(:agility, :integer, source: :agi)
    field(:stamina, :integer, source: :sta)
    field(:intellect, :integer, source: :inte)
    field(:spirit, :integer, source: :spi)
  end

  def get(race, class, level) do
    Mangos.Repo.get_by(__MODULE__, race: race, class: class, level: level)
  end
end
