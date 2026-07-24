defmodule ThistleTea.Game.Network.Message.SmsgSpellDelayed do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELL_DELAYED

  defstruct caster: 0,
            delay_ms: 0

  @impl ServerMessage
  def to_binary(%__MODULE__{caster: caster, delay_ms: delay_ms}) do
    <<caster::little-size(64), delay_ms::little-size(32)>>
  end
end
