defmodule ThistleTea.Game.Network.Message.SmsgItemTimeUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ITEM_TIME_UPDATE

  defstruct [:guid, :duration]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, duration: duration}) do
    <<guid::little-size(64), duration::little-size(32)>>
  end
end
