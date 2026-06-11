defmodule ThistleTea.Game.Network.Message.SmsgSpellCooldown do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELL_COOLDOWN

  defstruct [:guid, cooldowns: []]

  @impl ServerMessage
  def to_binary(%__MODULE__{guid: guid, cooldowns: cooldowns}) do
    <<guid::little-size(64)>> <>
      Enum.map_join(cooldowns, fn {spell_id, cooldown_ms} ->
        <<spell_id::little-size(32), cooldown_ms::little-size(32)>>
      end)
  end
end
