defmodule ThistleTea.Game.Network.Message.SmsgQuestupdateAddItem do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_QUESTUPDATE_ADD_ITEM

  defstruct [:item_id, :count]

  @impl ServerMessage
  def to_binary(%__MODULE__{item_id: item_id, count: count}) do
    <<item_id::little-size(32), count::little-size(32)>>
  end
end
