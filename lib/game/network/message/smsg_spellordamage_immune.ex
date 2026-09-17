defmodule ThistleTea.Game.Network.Message.SmsgSpellordamageImmune do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELLORDAMAGE_IMMUNE

  defstruct [:caster, :target, :spell_id]

  @impl ServerMessage
  def to_binary(%__MODULE__{caster: caster, target: target, spell_id: spell_id}) do
    <<caster::little-size(64), target::little-size(64), spell_id::little-size(32), 0::size(8)>>
  end
end
