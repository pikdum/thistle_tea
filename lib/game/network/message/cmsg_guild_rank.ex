defmodule ThistleTea.Game.Network.Message.CmsgGuildRank do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GUILD_RANK

  alias ThistleTea.Game.World.Entity.Player.Guilds

  defstruct [:rank_id, :rights, :name]

  @impl ClientMessage
  def handle(%__MODULE__{rank_id: rank_id, rights: rights, name: name}, state),
    do: Guilds.edit_rank(state, rank_id, rights, name)

  @impl ClientMessage
  def from_binary(<<rank_id::little-size(32), rights::little-size(32), payload::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(payload)
    %__MODULE__{rank_id: rank_id, rights: rights, name: name}
  end
end
