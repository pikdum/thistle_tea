defmodule ThistleTea.Game.Network.Message.MsgListStabledPetsClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_LIST_STABLED_PETS

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
