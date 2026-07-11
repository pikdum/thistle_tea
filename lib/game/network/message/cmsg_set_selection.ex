defmodule ThistleTea.Game.Network.Message.CmsgSetSelection do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SET_SELECTION

  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Reactive

  defstruct [:guid]

  @impl ClientMessage
  def handle(%__MODULE__{guid: guid}, %{character: %{unit: %Unit{} = unit} = character} = state) do
    character =
      character
      |> clear_old_combo_target(guid)
      |> then(&%{&1 | unit: %{unit | target: guid}})

    %{state | character: character, target: guid}
  end

  def handle(%__MODULE__{guid: guid}, state) do
    %{state | target: guid}
  end

  @impl ClientMessage
  def from_binary(payload) do
    <<guid::little-size(64)>> = payload

    %__MODULE__{
      guid: guid
    }
  end

  defp clear_old_combo_target(%{player: player} = character, guid) do
    if player.field_combo_target == guid, do: character, else: Reactive.consume_combo(character)
  end

  defp clear_old_combo_target(character, _guid), do: character
end
