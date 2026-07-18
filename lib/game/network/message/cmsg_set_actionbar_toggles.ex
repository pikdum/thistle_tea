defmodule ThistleTea.Game.Network.Message.CmsgSetActionbarToggles do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTIONBAR_TOGGLES

  alias ThistleTea.Game.Entity.Data.Component.Player

  defstruct [:action_bar]

  @impl ClientMessage
  def handle(
        %__MODULE__{action_bar: action_bar},
        %{character: %Character{player: %Player{} = player} = character} = state
      ) do
    %{state | character: %{character | player: %{player | action_bars: action_bar}}}
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<action_bar::little-size(8)>>) do
    %__MODULE__{action_bar: action_bar}
  end
end
