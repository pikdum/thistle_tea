defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMover do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTIVE_MOVER

  alias ThistleTea.Game.World.Visibility

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{guid: guid} = state) do
    enter_world(state)
  end

  def handle(%__MODULE__{guid: guid}, %{character: %Character{object: %{guid: guid}}} = state) do
    enter_world(state)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<guid::little-size(64)>>) do
    %__MODULE__{guid: guid}
  end

  defp enter_world(%{ready: true} = state), do: state

  defp enter_world(state) do
    state = Visibility.enter_player(%{state | ready: true})
    send(self(), :restore_active_pet)
    state
  end
end
