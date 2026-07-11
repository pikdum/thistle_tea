defmodule ThistleTea.Game.Network.Message.SmsgCooldownEvent do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_COOLDOWN_EVENT

  defstruct [:spell_id, :guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id, guid: guid}) do
    <<spell_id::little-size(32), guid::little-size(64)>>
  end
end
