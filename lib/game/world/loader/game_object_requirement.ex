defmodule ThistleTea.Game.World.Loader.GameObjectRequirement do
  @moduledoc """
  Boot-loaded `gameobject_requirement` rows, keyed by the gated spawn's guid.
  """

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.GameObject.UseRequirement

  @key {__MODULE__, :catalog}

  def load_all do
    catalog =
      Mangos.GameObjectRequirement
      |> Mangos.Repo.all()
      |> Enum.flat_map(fn row ->
        case UseRequirement.from_row(row.req_type, row.req_guid) do
          %UseRequirement{} = requirement -> [{row.guid, requirement}]
          nil -> []
        end
      end)
      |> Map.new()

    :persistent_term.put(@key, catalog)
    :ok
  end

  def get(db_guid), do: @key |> :persistent_term.get(%{}) |> Map.get(db_guid)
end
