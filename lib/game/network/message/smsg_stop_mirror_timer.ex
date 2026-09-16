defmodule ThistleTea.Game.Network.Message.SmsgStopMirrorTimer do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_STOP_MIRROR_TIMER

  defstruct [:timer]

  @impl ServerMessage
  def to_binary(%__MODULE__{timer: timer}), do: <<timer::little-size(32)>>
end
