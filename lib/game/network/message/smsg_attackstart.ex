defmodule ThistleTea.Game.Network.Message.SmsgAttackstart do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ATTACKSTART

  defstruct [
    :attacker,
    :victim
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{attacker: attacker, victim: victim}) do
    <<attacker::little-size(64), victim::little-size(64)>>
  end
end
