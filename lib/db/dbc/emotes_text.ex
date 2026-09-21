defmodule EmotesText do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :integer, autogenerate: false}
  schema "EmotesText" do
    field(:emote, :integer)
  end
end
