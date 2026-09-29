defmodule ThistleTea.Game.World.Inbound.Death do
  @moduledoc "Handles decoded corpse, spirit healer, and resurrection client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Battlegrounds
  alias ThistleTea.Game.World.Entity.Player.Corpses
  alias ThistleTea.Game.World.Entity.Player.Resurrection
  alias ThistleTea.Game.World.Entity.Player.SelfResurrection
  alias ThistleTea.Game.World.Entity.Player.SpiritHealer

  def messages do
    [
      Message.CmsgAreaSpiritHealerQuery,
      Message.CmsgAreaSpiritHealerQueue,
      Message.CmsgReclaimCorpse,
      Message.CmsgRepopRequest,
      Message.CmsgResurrectResponse,
      Message.CmsgSelfRes,
      Message.CmsgSpiritHealerActivate,
      Message.MsgCorpseQuery
    ]
  end

  def handle(%Message.CmsgAreaSpiritHealerQuery{guid: guid}, state), do: Battlegrounds.spirit_healer_time(state, guid)

  def handle(%Message.CmsgAreaSpiritHealerQueue{guid: guid}, state), do: Battlegrounds.queue_resurrection(state, guid)

  def handle(%Message.CmsgReclaimCorpse{}, state), do: Corpses.reclaim(state)

  def handle(%Message.CmsgRepopRequest{}, state), do: Corpses.release(state)

  def handle(%Message.CmsgResurrectResponse{guid: guid, status: status}, state),
    do: Resurrection.respond(state, guid, status)

  def handle(%Message.CmsgSelfRes{}, state), do: SelfResurrection.use(state)

  def handle(%Message.CmsgSpiritHealerActivate{guid: guid}, state), do: SpiritHealer.activate(state, guid)

  def handle(%Message.MsgCorpseQuery{}, state), do: Corpses.query(state)
end
