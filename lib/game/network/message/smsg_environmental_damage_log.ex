defmodule ThistleTea.Game.Network.Message.SmsgEnvironmentalDamageLog do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ENVIRONMENTALDAMAGELOG

  defstruct [:guid, :damage_type, :damage, absorb: 0, resist: 0]

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    <<message.guid::little-size(64), message.damage_type::little-size(8), message.damage::little-size(32),
      message.absorb::little-size(32), message.resist::little-size(32)>>
  end
end
