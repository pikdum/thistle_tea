defmodule ThistleTea.Game.Network.Message.SmsgNewTaxiPath do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_NEW_TAXI_PATH

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
