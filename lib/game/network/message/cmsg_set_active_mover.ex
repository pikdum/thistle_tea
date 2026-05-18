defmodule ThistleTea.Game.Network.Message.CmsgSetActiveMover do
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
    state
    |> Map.put(:ready, true)
    |> Visibility.enter_player()
  end
end
