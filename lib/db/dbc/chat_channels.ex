defmodule ChatChannels do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "ChatChannels" do
    field(:flags, :integer)
    field(:faction_group, :integer)
    field(:name, :string, source: :name_en_gb)
  end
end
