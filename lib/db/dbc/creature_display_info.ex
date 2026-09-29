defmodule ThistleTea.DB.DBC.CreatureDisplayInfo do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "CreatureDisplayInfo" do
    field(:model, :integer)
    field(:extended_display_info, :integer)
    field(:creature_model_scale, :float)
  end
end
