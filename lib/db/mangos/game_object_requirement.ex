defmodule ThistleTea.DB.Mangos.GameObjectRequirement do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:guid, :integer, autogenerate: false}
  schema "gameobject_requirement" do
    field(:req_type, :integer, source: :reqType)
    field(:req_guid, :integer, source: :reqGuid)
  end
end
