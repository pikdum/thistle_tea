defmodule ThistleTea.Game.Network.Message.SmsgSpellFailedOther do
  use ThistleTea.Game.Network.ServerMessage, :SMSG_SPELL_FAILED_OTHER

  defstruct [
    :caster,
    :id
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{caster: caster, id: id}) do
    <<caster::little-size(64), id::little-size(32)>>
  end
end
