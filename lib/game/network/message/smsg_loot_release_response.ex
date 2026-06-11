defmodule ThistleTea.Game.Network.Message.SmsgLootReleaseResponse do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_LOOT_RELEASE_RESPONSE

  defstruct [:guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid}) do
    <<guid::little-size(64), 1>>
  end
end
