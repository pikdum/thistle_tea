defmodule ThistleTea.Game.Network.Message.SmsgPetUnlearnConfirm do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PET_UNLEARN_CONFIRM

  defstruct [:pet_guid, :cost]

  @impl ServerMessage
  def to_binary(%__MODULE__{pet_guid: guid, cost: cost}), do: <<guid::little-size(64), cost::little-size(32)>>
end
