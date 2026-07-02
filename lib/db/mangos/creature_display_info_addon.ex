defmodule ThistleTea.DB.Mangos.CreatureDisplayInfoAddon do
  use Ecto.Schema

  import Ecto.Query

  alias ThistleTea.DB.Mangos

  @primary_key false
  schema "creature_display_info_addon" do
    field(:display_id, :integer, primary_key: true, default: 0)
    field(:build, :integer, primary_key: true, default: 0)
    field(:bounding_radius, :float, default: 0.0)
    field(:combat_reach, :float, default: 0.0)
    field(:speed_walk, :float, default: 1.0)
    field(:speed_run, :float, default: 1.14286)
    field(:gender, :integer, default: 2)
    field(:display_id_other_gender, :integer, default: 0)
  end

  def get(display_id) when is_integer(display_id) and display_id > 0 do
    __MODULE__
    |> where([row], row.display_id == ^display_id)
    |> order_by([row], desc: row.build)
    |> limit(1)
    |> Mangos.Repo.one()
  end

  def get(_display_id), do: nil
end
