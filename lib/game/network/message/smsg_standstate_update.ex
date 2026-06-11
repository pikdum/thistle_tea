defmodule ThistleTea.Game.Network.Message.SmsgStandstateUpdate do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_STANDSTATE_UPDATE

  defstruct [:stand_state]

  @impl ServerMessage
  def to_binary(%__MODULE__{stand_state: stand_state}) do
    <<stand_state>>
  end
end
