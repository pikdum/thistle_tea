defmodule ThistleTea.Game.Network.Message.SmsgExplorationExperience do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_EXPLORATION_EXPERIENCE

  defstruct [:area_id, experience: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.area_id::little-size(32), message.experience::little-size(32)>>
  end
end
