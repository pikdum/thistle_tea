defmodule ThistleTea.Game.Inbound.MsgTalentWipeConfirmClient do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :MSG_TALENT_WIPE_CONFIRM

  alias ThistleTea.Game.World.Entity.Player.TalentReset

  defstruct [:trainer_guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{trainer_guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{trainer_guid: guid}, state), do: TalentReset.complete(state, guid)
end
