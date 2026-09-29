defmodule ThistleTea.Game.World.Inbound.Travel do
  @moduledoc "Handles decoded taxi and summon client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Summoning
  alias ThistleTea.Game.World.Entity.Player.Taxi

  def messages do
    [
      Message.CmsgActivatetaxi,
      Message.CmsgActivatetaxiexpress,
      Message.CmsgMoveSplineDone,
      Message.CmsgSummonResponse,
      Message.CmsgTaxinodeStatusQuery,
      Message.CmsgTaxiqueryavailablenodes
    ]
  end

  def handle(
        %Message.CmsgActivatetaxi{guid: guid, source_node: source, destination_node: destination},
        %{ready: true, character: %Character{}} = state
      ) do
    Taxi.activate(state, guid, [source, destination])
  end

  def handle(%Message.CmsgActivatetaxi{}, state), do: state

  def handle(
        %Message.CmsgActivatetaxiexpress{guid: guid, nodes: nodes},
        %{ready: true, character: %Character{}} = state
      ) do
    Taxi.activate(state, guid, nodes)
  end

  def handle(%Message.CmsgActivatetaxiexpress{}, state), do: state

  def handle(%Message.CmsgMoveSplineDone{spline_id: spline_id}, state), do: Taxi.spline_done(state, spline_id)

  def handle(%Message.CmsgSummonResponse{summoner_guid: summoner_guid}, state) do
    Summoning.accept(state, summoner_guid)
  end

  def handle(%Message.CmsgTaxinodeStatusQuery{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Taxi.status(state, guid)
  end

  def handle(%Message.CmsgTaxinodeStatusQuery{}, state), do: state

  def handle(%Message.CmsgTaxiqueryavailablenodes{guid: guid}, %{ready: true, character: %Character{}} = state) do
    Taxi.query(state, guid)
  end

  def handle(%Message.CmsgTaxiqueryavailablenodes{}, state), do: state
end
