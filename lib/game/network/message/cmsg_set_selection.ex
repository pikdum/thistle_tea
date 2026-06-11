defmodule ThistleTea.Game.Network.Message.CmsgSetSelection do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_SELECTION

  alias ThistleTea.Game.Entity.Data.Component.Unit

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{character: %{unit: %Unit{} = unit} = character} = state) do
    character = %{character | unit: %{unit | target: guid}}

    state
    |> Map.put(:character, character)
    |> Map.put(:target, guid)
  end

  def handle(%__MODULE__{guid: guid}, state) do
    Map.put(state, :target, guid)
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end
end
