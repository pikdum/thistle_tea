defmodule ThistleTea.Game.Network.Message.CmsgAttackswing do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_ATTACKSWING

  alias ThistleTea.Game.Player.Attacking

  defstruct [:target_guid]

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target}, state), do: Attacking.start(state, target)

  @impl ClientMessage
  def from_binary(<<target_guid::little-size(64)>>), do: %__MODULE__{target_guid: target_guid}
end
