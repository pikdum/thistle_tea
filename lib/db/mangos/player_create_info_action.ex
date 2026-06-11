defmodule ThistleTea.DB.Mangos.PlayerCreateInfoAction do
  use Ecto.Schema

  import Bitwise, only: [<<<: 2, |||: 2]
  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "playercreateinfo_action" do
    field(:race, :integer)
    field(:class, :integer)
    field(:button, :integer)
    field(:action, :integer)
    field(:type, :integer)
  end

  def get_all(race, class) do
    query =
      from(p in Mangos.PlayerCreateInfoAction,
        where: p.race == ^race and p.class == ^class,
        select: {p.button, p.action, p.type}
      )

    Mangos.Repo.all(query)
    |> Map.new(fn {button, action, type} -> {button, action ||| type <<< 24} end)
  end
end
