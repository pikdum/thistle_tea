defmodule ThistleTea.Game.Network.Message.MsgTalentWipeConfirmClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_TALENT_WIPE_CONFIRM

  defstruct [:trainer_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{trainer_guid: guid}
end
