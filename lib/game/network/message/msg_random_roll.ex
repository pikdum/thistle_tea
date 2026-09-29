defmodule ThistleTea.Game.Network.Message.MsgRandomRoll do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_RANDOM_ROLL

  alias ThistleTea.Game.World.Entity.Player.Groups

  defstruct [:minimum, :maximum]

  @impl ClientMessage
  def from_binary(<<minimum::little-size(32), maximum::little-size(32)>>) do
    %__MODULE__{minimum: minimum, maximum: maximum}
  end

  @impl ClientMessage
  def handle(%__MODULE__{minimum: minimum, maximum: maximum}, state) do
    Groups.random_roll(state, minimum, maximum)
  end
end
