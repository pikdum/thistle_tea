defmodule ThistleTea.Game.Inbound.CmsgTrainerList do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_TRAINER_LIST

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.Training

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Training.send_list(state, guid)
  end

  def handle(%__MODULE__{}, state), do: state
end
