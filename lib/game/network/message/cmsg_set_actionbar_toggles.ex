defmodule ThistleTea.Game.Network.Message.CmsgSetActionbarToggles do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_ACTIONBAR_TOGGLES

  defstruct [:action_bar]

  @impl ClientMessage
  def from_binary(<<action_bar::little-size(8)>>) do
    %__MODULE__{action_bar: action_bar}
  end
end
