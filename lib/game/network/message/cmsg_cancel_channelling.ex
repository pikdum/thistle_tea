defmodule ThistleTea.Game.Network.Message.CmsgCancelChannelling do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_CANCEL_CHANNELLING

  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT.Spell, as: SpellBT
  alias ThistleTea.Game.Spell.Cast

  require Logger

  defstruct [:spell_id]

  @impl ClientMessage
  def handle(%__MODULE__{}, %{character: character} = state) do
    case Map.get(character.internal, :casting) do
      %Cast{} ->
        character =
          character
          |> SpellBT.clear_cast()
          |> EventSink.emit_pending()

        %{state | character: character}

      _ ->
        state
    end
  end

  def handle(%__MODULE__{}, state), do: state

  @impl ClientMessage
  def from_binary(<<spell_id::little-size(32), _rest::binary>>) do
    %__MODULE__{spell_id: spell_id}
  end

  def from_binary(_payload), do: %__MODULE__{}
end
