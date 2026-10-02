defmodule ThistleTea.Game.Inbound.CmsgGmticketUpdatetext do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMTICKET_UPDATETEXT, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Tickets

  defstruct [:type, :message]

  @impl ClientMessage
  def from_binary(<<type::8, rest::binary>>) do
    {:ok, message, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{type: type, message: message}
  end

  @impl ClientMessage
  def handle(%__MODULE__{type: type, message: message}, state), do: Tickets.update_text(state, type, message)
end
