defmodule ThistleTea.Game.Network.Message.CmsgSetFactionAtwar do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_FACTION_ATWAR

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Player.Reputation

  defstruct [:index, :flags]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{character: %Character{internal: %{in_combat: true}}} = state), do: state

  def handle(%__MODULE__{index: index, flags: flags}, %{ready: true} = state) do
    Reputation.set_at_war(state, index, (flags &&& 0x02) != 0)
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<index::little-size(32), flags>>) do
    %__MODULE__{index: index, flags: flags}
  end
end
