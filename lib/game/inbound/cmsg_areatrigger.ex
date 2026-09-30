defmodule ThistleTea.Game.Inbound.CmsgAreatrigger do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_AREATRIGGER

  alias ThistleTea.Game.World.Entity.Player.AreaTriggers

  defstruct [:trigger_id]

  @impl ClientMessage
  def from_binary(payload) do
    <<trigger_id::little-size(32)>> = payload

    %__MODULE__{
      trigger_id: trigger_id
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{trigger_id: trigger_id}, state), do: AreaTriggers.handle(state, trigger_id)
end
