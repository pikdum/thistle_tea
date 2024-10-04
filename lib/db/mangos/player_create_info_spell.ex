defmodule PlayerCreateInfoSpell do
  use Ecto.Schema
  import Ecto.Query

  @primary_key false
  schema "playercreateinfo_spell" do
    field(:race, :integer)
    field(:class, :integer)
    field(:spell, :integer)
    field(:note, :string)
  end

  def get_all(race, class) do
    query =
      from(p in PlayerCreateInfoSpell,
        where: p.race == ^race and p.class == ^class,
        select: p.spell
      )

    ThistleTea.Mangos.all(query)
  end
end
