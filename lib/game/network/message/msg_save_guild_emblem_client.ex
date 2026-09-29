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
