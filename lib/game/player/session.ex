defmodule ThistleTea.Game.Player.Session do
  @moduledoc """
  Player-session teardown on logout or disconnect: persists the character,
  deregisters from world systems and chat channels, notifies the party, and
  resets the connection state.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  def leave_world(state) do
    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    if Map.get(state, :character) do
      CharacterStore.put(state.character)
    end

    if Map.get(state, :guid) do
      Entity.unregister(state.guid)
      Metadata.delete(state.guid)
      SpatialHash.remove(:players, state.guid)
      state = Visibility.leave_player(state)

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

      for guid <- Map.get(state, :player_guids, []) do
        # credo:disable-for-next-line Credo.Check.Refactor.Nesting
        if guid != state.guid do
          Entity.destroy_object(guid, state.guid)
        end
      end
    end

    %{
      account: Map.get(state, :account),
      conn: Map.get(state, :conn)
    }
  end
end
