defmodule ThistleTea.Game.Network.Message.CmsgTrainerList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TRAINER_LIST

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
