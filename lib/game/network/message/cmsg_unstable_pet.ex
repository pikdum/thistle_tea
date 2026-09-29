defmodule ThistleTea.Game.Network.Message.CmsgUnstablePet do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_UNSTABLE_PET

  defstruct [:guid, :pet_number]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), pet_number::little-size(32)>>),
    do: %__MODULE__{guid: guid, pet_number: pet_number}
end
