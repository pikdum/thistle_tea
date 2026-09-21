defmodule ThistleTea.Game.Network.Message.SmsgIgnoreList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_IGNORE_LIST

  defstruct guids: []

  @impl ServerMessage
  def to_binary(%__MODULE__{guids: guids}) do
    IO.iodata_to_binary([<<length(guids)>> | Enum.map(guids, &<<&1::little-size(64)>>)])
  end
end
