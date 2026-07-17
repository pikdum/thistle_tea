defmodule ThistleTea.Game.Network.Message.CmsgSelfRes do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_SELF_RES

  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Network.InventoryUpdate
  alias ThistleTea.Game.Network.Server
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Visibility

  @reincarnation_spell_id 21_169
  @ankh_item_id 17_030
  @restore_percent 0.2

  defstruct []

  @impl ClientMessage
  def handle(
        %__MODULE__{},
        %{ready: true, character: %Character{player: %{self_res_spell: @reincarnation_spell_id}} = character} = state
      ) do
    if Core.dead?(character) and not Death.ghost?(character) do
      reincarnate(state, character)
    else
      state
    end
  end

  def handle(_message, state), do: state

  @impl ClientMessage
  def from_binary(_payload), do: %__MODULE__{}

  defp reincarnate(state, character) do
    case Inventory.remove_count(character.player, @ankh_item_id, 1, &ItemStore.get/1) do
      {:ok, result} ->
        state = InventoryUpdate.apply(state, {:ok, result})
        {character, events} = Death.resurrect(state.character, @restore_percent, Time.now())
        character = EventSink.emit(character, events)
        state = Server.maybe_broadcast_update(%{state | character: character})
        Visibility.notify_visibility_changed(character)
        Visibility.resync_player(state)

      _ ->
        state
    end
  end
end
