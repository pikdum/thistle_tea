defmodule ThistleTea.DB.Mangos.QuestGreeting do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "quest_greeting" do
    field(:entry, :integer, primary_key: true)
    field(:type, :integer, primary_key: true)
    field(:content_default, :string)
    field(:emote_id, :integer)
    field(:emote_delay, :integer)
  end
end
