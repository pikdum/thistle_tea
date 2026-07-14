defmodule ThistleTea.Game.Network.Message.CmsgCancelChannelling do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CHANNELLING

  alias ThistleTea.Game.Player.Spellcasting

  defstruct [:spell_id]

  @impl ClientMessage
  def handle(%__MODULE__{}, state), do: Spellcasting.cancel_cast_request(state)

  @impl ClientMessage
  def from_binary(<<spell_id::little-size(32), _rest::binary>>) do
    %__MODULE__{spell_id: spell_id}
  end

  def from_binary(_payload), do: %__MODULE__{}
end
