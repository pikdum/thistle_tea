defmodule ThistleTea.Game.Network.Message.SmsgFishEscaped do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FISH_ESCAPED

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
