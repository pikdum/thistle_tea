defmodule ThistleTea.Game.Network.Message.SmsgUpdateWorldState do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_UPDATE_WORLD_STATE

  defstruct [:state, :value]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.state::little-size(32), message.value::little-size(32)>>
  end
end
