defmodule ThistleTea.Game.Network.Message.CmsgLogoutRequest do
  @moduledoc false
  use ThistleTea.Game.Network.ClientMessage, :CMSG_LOGOUT_REQUEST

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  require Logger

  defstruct []

  @impl ClientMessage
  def handle(%__MODULE__{}, state) do
    Logger.info("CMSG_LOGOUT_REQUEST")
    Network.send_packet(%Message.SmsgLogoutResponse{result: 0, speed: 0})
    logout_timer = Process.send_after(self(), :logout_complete, 1_000)
    Map.put(state, :logout_timer, logout_timer)
  end

  @impl ClientMessage
  def from_binary(_payload) do
    %__MODULE__{}
  end

  def handle_logout(state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    # save current character state
    if Map.get(state, :character) do
      CharacterStore.put(state.character)
    end

    if Map.get(state, :guid) do
      Entity.unregister(state.guid)
      Metadata.delete(state.guid)
      # remove from map
      SpatialHash.remove(:players, state.guid)
      state = Visibility.leave_player(state)

      # leave all chat channels
      ThistleTea.ChatChannel
      |> Registry.keys(self())
      |> Enum.each(fn channel ->
        ThistleTea.ChatChannel
        |> Registry.unregister(channel)
      end)

      case PartySystem.group_of(state.guid) do
        %Group{} = group -> Notifier.send_group_list(group)
        _ -> :ok
      end

      # broadcast destroy object
      for guid <- Map.get(state, :player_guids, []) do
        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        if guid != state.guid do
          Entity.destroy_object(guid, state.guid)
        end
      end
    end

    # reset state so nothing lingers
    %{
      account: Map.get(state, :account),
      conn: Map.get(state, :conn)
    }
  end
end
