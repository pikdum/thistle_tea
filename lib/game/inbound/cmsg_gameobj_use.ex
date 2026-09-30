defmodule ThistleTea.Game.Inbound.CmsgGameobjUse do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_GAMEOBJ_USE

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.World.Entity.Player.GameObjects

  defstruct [:guid]

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64), _rest::binary>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{ready: true, character: %Character{}} = state) do
    GameObjects.use_object(state, guid)
  end

  def handle(%__MODULE__{}, state), do: state
end
