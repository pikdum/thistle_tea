defmodule ThistleTea.Game.Network.Message.MsgSaveGuildEmblemClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_SAVE_GUILD_EMBLEM

  alias ThistleTea.Game.Player.Guilds

  defstruct [:vendor_guid, :emblem]

  @impl ClientMessage
  def from_binary(
        <<vendor_guid::little-size(64), style::little-size(32), color::little-size(32), border::little-size(32),
          border_color::little-size(32), background::little-size(32)>>
      ) do
    %__MODULE__{vendor_guid: vendor_guid, emblem: {style, color, border, border_color, background}}
  end

  @impl ClientMessage
  def handle(%__MODULE__{vendor_guid: vendor_guid, emblem: emblem}, state),
    do: Guilds.save_emblem(state, vendor_guid, emblem)
end

defmodule ThistleTea.Game.Network.Message.MsgSaveGuildEmblemServer do
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
