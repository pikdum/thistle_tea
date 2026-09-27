defmodule ThistleTea.Game.Network.Message.SmsgItemCooldown do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_ITEM_COOLDOWN

  defstruct [:item_guid, :spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{item_guid: guid, spell_id: spell_id}) do
    <<guid::little-size(64), spell_id::little-size(32)>>
  end
end
