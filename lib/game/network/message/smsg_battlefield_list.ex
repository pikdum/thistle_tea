defmodule ThistleTea.Game.Network.Message.SmsgBattlefieldList do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_BATTLEFIELD_LIST

  defstruct [:guid, :map, :bracket, instances: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    instances = Enum.map_join(message.instances, &<<&1::little-size(32)>>)

    <<message.guid::little-size(64), message.map::little-size(32), message.bracket::little-size(8),
      length(message.instances)::little-size(32)>> <> instances
  end
end
