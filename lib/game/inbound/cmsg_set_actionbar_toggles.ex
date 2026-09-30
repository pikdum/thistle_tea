defmodule ThistleTea.Game.Inbound.CmsgSetActionbarToggles do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_SET_ACTIONBAR_TOGGLES

  alias ThistleTea.Game.World.Entity.Player.ActionBar

  defstruct [:action_bar]

  @impl ClientMessage
  def from_binary(<<action_bar::little-size(8)>>) do
    %__MODULE__{action_bar: action_bar}
  end

  @impl ClientMessage
  def handle(%__MODULE__{action_bar: action_bar}, state), do: ActionBar.set_toggles(state, action_bar)
end
