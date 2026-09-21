defmodule ThistleTea.Game.Entity.Data.Emote do
  @moduledoc """
  A client animation and whether it occupies the persistent unit emote field.
  """

  @enforce_keys [:id]
  defstruct [:id, persistent?: false]
end
