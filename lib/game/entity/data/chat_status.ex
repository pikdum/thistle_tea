defmodule ThistleTea.Game.Entity.Data.ChatStatus do
  @moduledoc """
  Session chat availability and the automatic reply shown to whisper senders.
  """

  defstruct mode: :available, message: ""
end
