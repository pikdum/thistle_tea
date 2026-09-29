defmodule ThistleTea.Game.Network.Message.CmsgStablePet do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_STABLE_PET

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
