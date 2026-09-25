defmodule ThistleTea.Game.Network.Message.CmsgBattlefieldJoin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEFIELD_JOIN

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:map, instance_id: 0, join_as_group: false]

  @impl ClientMessage
  def handle(%__MODULE__{map: map, instance_id: instance_id, join_as_group: join_as_group}, state) do
    Battlegrounds.join(state, map, join_as_group, instance_id)
  end

  @impl ClientMessage
  def from_binary(<<map::little-size(32)>>), do: %__MODULE__{map: map}

  def from_binary(<<map::little-size(32), instance_id::little-size(32), join_as_group::little-size(8)>>) do
    %__MODULE__{map: map, instance_id: instance_id, join_as_group: join_as_group != 0}
  end
end
