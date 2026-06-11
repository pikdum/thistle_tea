defmodule ThistleTea.Game.Network.Message.SmsgLogoutComplete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOGOUT_COMPLETE

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}) do
    <<>>
  end
end
