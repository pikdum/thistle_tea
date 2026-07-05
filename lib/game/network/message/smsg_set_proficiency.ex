defmodule ThistleTea.Game.Network.Message.SmsgSetProficiency do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SET_PROFICIENCY

  defstruct [:item_class, :subclass_mask]

  @impl ServerMessage
  def to_binary(%__MODULE__{item_class: item_class, subclass_mask: subclass_mask}) do
    <<item_class::size(8), subclass_mask::little-size(32)>>
  end
end
