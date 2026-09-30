defmodule ThistleTea.Game.Inbound.CmsgSetsheathed do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SETSHEATHED

  alias ThistleTea.Game.World.Entity.Player.Attacking

  defstruct [:sheath_state]

  @impl ClientMessage
  def from_binary(payload) do
    <<sheath_state::little-size(32)>> = payload

    %__MODULE__{
      sheath_state: sheath_state
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{sheath_state: sheath_state}, state), do: Attacking.sheathe(state, sheath_state)
end
