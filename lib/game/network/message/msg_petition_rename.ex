defmodule ThistleTea.Game.Network.Message.MsgPetitionRename do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :MSG_PETITION_RENAME

  defstruct [:item_guid, :name]

  @impl ServerMessage
  def to_binary(%__MODULE__{item_guid: item_guid, name: name}), do: <<item_guid::little-size(64)>> <> name <> <<0>>
end
