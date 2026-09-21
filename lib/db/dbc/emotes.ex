defmodule Emotes do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "Emotes" do
    field(:spec_proc, :integer)
  end
end
