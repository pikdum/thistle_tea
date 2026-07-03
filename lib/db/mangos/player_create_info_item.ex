defmodule ThistleTea.DB.Mangos.PlayerCreateInfoItem do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "playercreateinfo_item" do
    field(:race, :integer)
    field(:class, :integer)
    field(:item_id, :integer, source: :itemid)
    field(:amount, :integer)
  end

  def get_all(race, class) do
    query =
      from(p in Mangos.PlayerCreateInfoItem,
        where: p.race == ^race and p.class == ^class,
        select: %{item_id: p.item_id, amount: p.amount},
        order_by: p.item_id
      )

    Mangos.Repo.all(query)
  end
end
