defmodule ThistleTea.Game.Message.SmsgSpellFailure do
  use ThistleTea.Game.ServerMessage, :SMSG_SPELL_FAILURE

  defstruct [
    :guid,
    :spell,
    :result
  ]

  @impl ServerMessage
  def to_binary(%__MODULE__{
        guid: guid,
        spell: spell,
        result: result
      }) do
    <<guid::little-size(64), spell::little-size(32), result::little-size(8)>>
  end
end
