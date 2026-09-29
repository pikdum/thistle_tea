defmodule ThistleTea.Game.World.Inbound.Pvp do
  @moduledoc "Handles decoded battleground and PvP flag client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Battlegrounds
  alias ThistleTea.Game.World.Entity.Player.Pvp

  def messages do
    [
      Message.CmsgBattlefieldJoin,
      Message.CmsgBattlefieldList,
      Message.CmsgBattlefieldPort,
      Message.CmsgBattlefieldStatus,
      Message.CmsgBattlegroundPlayerPositions,
      Message.CmsgBattlemasterHello,
      Message.CmsgBattlemasterJoin,
      Message.CmsgLeaveBattlefield,
      Message.CmsgPvpLogData,
      Message.CmsgTogglePvp
    ]
  end

  def handle(%Message.CmsgBattlefieldJoin{map: map, instance_id: instance_id, join_as_group: join_as_group}, state) do
    Battlegrounds.join(state, map, join_as_group, instance_id)
  end

  def handle(%Message.CmsgBattlefieldList{map: map}, state), do: Battlegrounds.list(state, map)

  def handle(%Message.CmsgBattlefieldPort{action: action}, state), do: Battlegrounds.port(state, action)

  def handle(%Message.CmsgBattlefieldStatus{}, state), do: Battlegrounds.send_status(state)

  def handle(%Message.CmsgBattlegroundPlayerPositions{}, state), do: Battlegrounds.positions(state)

  def handle(%Message.CmsgBattlemasterHello{guid: guid}, state), do: Battlegrounds.battlemaster_hello(state, guid)

  def handle(%Message.CmsgBattlemasterJoin{map: map, instance_id: instance_id, join_as_group: join_as_group}, state) do
    Battlegrounds.join(state, map, join_as_group, instance_id)
  end

  def handle(%Message.CmsgLeaveBattlefield{}, state), do: Battlegrounds.leave(state)

  def handle(%Message.CmsgPvpLogData{}, state), do: Battlegrounds.scoreboard(state)

  def handle(%Message.CmsgTogglePvp{enabled: enabled}, state), do: Pvp.toggle(state, enabled)
end
