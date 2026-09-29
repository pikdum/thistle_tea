defmodule ThistleTea.Game.Network.Message.SmsgPetitionShowlist do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PETITION_SHOWLIST

  defstruct [:npc_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{npc_guid: guid}) do
    <<guid::little-size(64), 1::8, 1::little-size(32), 5863::little-size(32), 16_161::little-size(32),
      1000::little-size(32), 1::little-size(32)>>
  end
end
