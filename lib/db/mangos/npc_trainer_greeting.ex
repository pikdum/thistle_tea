defmodule ThistleTea.DB.Mangos.NpcTrainerGreeting do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:entry, :integer, autogenerate: false}
  schema "npc_trainer_greeting" do
    field(:content_default, :string)
  end
end
