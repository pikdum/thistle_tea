defmodule ThistleTea.Game.Network.Message.MsgSaveGuildEmblem do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_SAVE_GUILD_EMBLEM

  defstruct [:result]

  @results %{
    ok: 0,
    invalid_emblem: 1,
    not_in_guild: 2,
    not_leader: 3,
    not_enough_money: 4,
    invalid_vendor: 5
  }

  @impl ServerMessage
  def to_binary(%__MODULE__{result: result}), do: <<Map.fetch!(@results, result)::little-size(32)>>
end
