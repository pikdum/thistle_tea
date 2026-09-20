defmodule ThistleTea.Game.Network.Message.MsgTalentWipeConfirm do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_TALENT_WIPE_CONFIRM

  defstruct trainer_guid: 0, cost: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{trainer_guid: guid, cost: cost}), do: <<guid::little-size(64), cost::little-size(32)>>
end
