defmodule ThistleTea.Game.Inbound.CmsgGuildInfoText do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GUILD_INFO_TEXT

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:info]

  @impl ClientMessage
  def from_binary(payload) do
    {:ok, info, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{info: info}
  end

  @impl ClientMessage
  def handle(%__MODULE__{info: info}, state), do: Guilds.set_info(state, info)
end
