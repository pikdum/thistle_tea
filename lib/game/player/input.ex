defmodule ThistleTea.Game.Player.Input do
  @moduledoc "Keeps connection and query traffic available while a possessed player's gameplay input is suspended."

  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Network.Message

  @uncontrolled_messages [
    Message.CmsgPing,
    Message.CmsgMessagechat,
    Message.CmsgLogoutRequest,
    Message.CmsgLogoutCancel,
    Message.CmsgNameQuery,
    Message.CmsgCreatureQuery,
    Message.CmsgGameobjectQuery,
    Message.CmsgItemQuerySingle,
    Message.CmsgItemNameQuery,
    Message.CmsgItemTextQuery,
    Message.CmsgNpcTextQuery,
    Message.CmsgPetNameQuery,
    Message.CmsgQuestQuery,
    Message.CmsgQueryTime,
    Message.CmsgSetActiveMover,
    Message.CmsgMoveNotActiveMover,
    Message.CmsgFarSight,
    Message.CmsgForceRunSpeedChangeAck,
    Message.CmsgForceRunBackSpeedChangeAck,
    Message.CmsgForceSwimSpeedChangeAck,
    Message.CmsgForceSwimBackSpeedChangeAck,
    Message.CmsgForceMoveRootAck,
    Message.CmsgForceMoveUnrootAck,
    Message.CmsgMoveKnockBackAck,
    Message.CmsgMoveFeatherFallAck,
    Message.CmsgMoveWaterWalkAck,
    Message.CmsgMoveHoverAck
  ]

  def handle(message, state) do
    if allowed?(message, state), do: Message.handle(message, state), else: state
  end

  def allowed?(%module{}, %{character: character}) do
    not PlayerPossession.active?(character) or module in @uncontrolled_messages
  end

  def allowed?(_message, _state), do: true
end
