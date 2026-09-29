defmodule ThistleTea.Game.Network.Message.CmsgGuildSetOfficerNote do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_SET_OFFICER_NOTE

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:name, :note]

  @impl ClientMessage
  def handle(%__MODULE__{name: name, note: note}, state), do: Guilds.set_note(state, name, :officer_note, note)

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, name, rest} = BinaryUtils.parse_string(payload)
    {:ok, note, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{name: name, note: note}
  end
end
