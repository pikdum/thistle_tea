defmodule ThistleTea.Game.Network.Message.SmsgClearCooldown do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_CLEAR_COOLDOWN

  defstruct [:spell_id, :target_guid]

  @impl ServerMessage
  def to_binary(%__MODULE__{spell_id: spell_id, target_guid: target_guid}) do
    <<spell_id::little-size(32), target_guid::little-size(64)>>
  end
end
