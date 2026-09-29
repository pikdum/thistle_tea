defmodule ThistleTea.Game.World.Inbound.Combat do
  @moduledoc "Handles decoded melee attack and duel client messages."

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Attacking
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  def messages do
    [
      Message.CmsgAttackstop,
      Message.CmsgAttackswing,
      Message.CmsgDuelAccepted,
      Message.CmsgDuelCancelled
    ]
  end

  def handle(%Message.CmsgAttackstop{}, state), do: Attacking.stop(state)

  def handle(%Message.CmsgAttackswing{target_guid: target}, state), do: Attacking.start(state, target)

  def handle(%Message.CmsgDuelAccepted{}, %{ready: true, guid: guid} = state) do
    DuelSystem.accept(guid)
    state
  end

  def handle(%Message.CmsgDuelAccepted{}, state), do: state

  def handle(%Message.CmsgDuelCancelled{}, %{ready: true, guid: guid} = state) do
    DuelSystem.cancel(guid)
    state
  end

  def handle(%Message.CmsgDuelCancelled{}, state), do: state
end
