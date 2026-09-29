defmodule ThistleTea.Game.Network.Message.MsgPetitionRenameClient do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :MSG_PETITION_RENAME

  defstruct [:item_guid, :name]

  @impl ClientMessage
  def from_binary(<<guid::little-size(64), rest::binary>>) do
    {:ok, name, _rest} = BinaryUtils.parse_string(rest)
    %__MODULE__{item_guid: guid, name: name}
  end
end
