defmodule ThistleTea.Game.Network.Message.SmsgFishNotHooked do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FISH_NOT_HOOKED

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
