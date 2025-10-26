defmodule ThistleTea.Game.Message.SmsgAttackstop do
  use ThistleTea.Game.ServerMessage, :SMSG_ATTACKSTOP

  alias ThistleTea.Util

  defstruct [
    :player,
    :enemy,
    unknown1: 0
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{player: player, enemy: enemy, unknown1: unknown1}) do
    Util.pack_guid(player) <> Util.pack_guid(enemy) <> <<unknown1::little-size(32)>>
  end
end
