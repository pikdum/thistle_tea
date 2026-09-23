defmodule ThistleTea.Game.Network.Message.SmsgGuildInvite do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_GUILD_INVITE

  defstruct [:inviter_name, :guild_name]

  @impl ServerMessage
  def to_binary(%__MODULE__{inviter_name: inviter, guild_name: guild}) do
    inviter <> <<0>> <> guild <> <<0>>
  end
end
