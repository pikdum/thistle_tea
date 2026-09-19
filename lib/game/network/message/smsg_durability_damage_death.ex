defmodule ThistleTea.Game.Network.Message.SmsgDurabilityDamageDeath do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_DURABILITY_DAMAGE_DEATH

  defstruct []

  @impl ServerMessage
  def to_binary(%__MODULE__{}), do: <<>>
end
