defmodule ThistleTea.Game.Network.Message.CmsgBattlemasterJoin do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_BATTLEMASTER_JOIN

  alias ThistleTea.Game.Player.Battlegrounds

  defstruct [:guid, :map, :instance_id, :join_as_group]

  @impl ClientMessage
  def handle(%__MODULE__{map: map, instance_id: instance_id, join_as_group: join_as_group}, state) do
    Battlegrounds.join(state, map, join_as_group, instance_id)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), map::little-size(32), instance_id::little-size(32), join_as_group::little-size(8)>> =
      payload

    %__MODULE__{guid: guid, map: map, instance_id: instance_id, join_as_group: join_as_group != 0}
  end
end
