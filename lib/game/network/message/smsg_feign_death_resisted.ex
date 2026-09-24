defmodule ThistleTea.Game.Network.Message.SmsgFeignDeathResisted do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_FEIGN_DEATH_RESISTED

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
