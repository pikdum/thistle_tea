defmodule ThistleTea.Game.Network.Message.SmsgDuelComplete do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DUEL_COMPLETE

  defstruct started?: false

  @impl ServerMessage
  def to_binary(%__MODULE__{started?: started?}) do
    <<if(started?, do: 1, else: 0)::little-size(8)>>
  end
end
