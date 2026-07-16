defmodule ThistleTea.Game.Network.Message.SmsgUpdateLastInstance do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_UPDATE_LAST_INSTANCE

  defstruct [:map]

  @impl ServerMessage
  def to_binary(%__MODULE__{map: map}) do
    <<map::little-size(32)>>
  end
end
