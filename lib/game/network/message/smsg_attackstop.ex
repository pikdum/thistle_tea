defmodule ThistleTea.Game.Network.Message.SmsgAttackstop do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ATTACKSTOP

  defstruct [
    :player,
    :enemy,
    unknown1: 0
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{player: player, enemy: enemy, unknown1: unknown1}) do
    BinaryUtils.pack_guid(player) <> BinaryUtils.pack_guid(enemy) <> <<unknown1::little-size(32)>>
  end
end
