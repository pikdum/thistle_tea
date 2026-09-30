defmodule ThistleTea.Game.Inbound.CmsgAttackswing do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_ATTACKSWING

  alias ThistleTea.Game.World.Entity.Player.Attacking

  defstruct [:target_guid]

  @impl ClientMessage
  def from_binary(<<target_guid::little-size(64)>>), do: %__MODULE__{target_guid: target_guid}

  @impl ClientMessage
  def handle(%__MODULE__{target_guid: target}, state), do: Attacking.start(state, target)
end
