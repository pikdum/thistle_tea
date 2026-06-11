defmodule ThistleTea.Game.Network.Message.CmsgGameobjUse do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_GAMEOBJ_USE

  alias ThistleTea.Game.Entity

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{} = character} = state) do
    Entity.use_game_object(guid, state.guid, character.unit.level)
    state
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), _rest::binary>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
