defmodule ThistleTea.Game.Inbound.CmsgGmticketCreate do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, opcode: :CMSG_GMTICKET_CREATE, while_possessed: true

  alias ThistleTea.Game.World.Entity.Player.Tickets

  defstruct [:type, :map_id, :position, :message]

  @impl ClientMessage
  def from_binary(
        <<type::8, map_id::little-size(32), x::little-float-size(32), y::little-float-size(32),
          z::little-float-size(32), rest::binary>>
      ) do
    {:ok, message, _reserved} = BinaryUtils.parse_string(rest)
    %__MODULE__{type: type, map_id: map_id, position: {x, y, z}, message: message}
  end

  @impl ClientMessage
  def handle(%__MODULE__{} = message, state),
    do: Tickets.create(state, message.type, message.map_id, message.position, message.message)
end
