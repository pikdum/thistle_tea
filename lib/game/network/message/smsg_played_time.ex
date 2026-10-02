defmodule ThistleTea.Game.Network.Message.SmsgPlayedTime do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PLAYED_TIME

  defstruct [:total, :level]

  @impl ServerMessage
  def to_binary(%__MODULE__{total: total, level: level}), do: <<total::little-size(32), level::little-size(32)>>
end
