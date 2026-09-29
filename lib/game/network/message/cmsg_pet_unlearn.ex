defmodule ThistleTea.Game.Network.Message.CmsgPetUnlearn do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_PET_UNLEARN

  defstruct [:pet_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{pet_guid: guid}
end
