defmodule ThistleTea.Game.Network.Message.CmsgTrainerList do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_TRAINER_LIST

  alias ThistleTea.Game.Player.Training

  defstruct [:guid]

  defdelegate send_list(state, guid), to: Training

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Training.send_list(state, guid)
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>), do: %__MODULE__{guid: guid}
end
