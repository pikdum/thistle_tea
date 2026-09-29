defmodule ThistleTea.Game.Network.Message.MsgRandomRoll do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_RANDOM_ROLL

  defstruct [:minimum, :maximum]

  @impl ClientMessage
  def from_binary(<<minimum::little-size(32), maximum::little-size(32)>>) do
    %__MODULE__{minimum: minimum, maximum: maximum}
  end
end
