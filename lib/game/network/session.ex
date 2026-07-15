defmodule ThistleTea.Game.Network.Session do
  @moduledoc """
  Connection-handler state for one client session: the network connection,
  account, logged-in character, and world-presence bookkeeping (visibility
  cells, tracked entities, timers). `leave_world/1` tears the session down on
  logout or disconnect — persisting the character, deregistering from world
  systems and chat channels, notifying the party — and resets to a bare
  session keeping only the connection and account.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.ChatChannels
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  defstruct [
    :conn,
    :account,
    :guid,
    :packed_guid,
    :character,
    :visibility_cells,
    :player_tick_ref,
    :logout_timer,
    :target,
    :latency,
    :loot_guid,
    :pending_repop,
    :next_exploration_check_at,
    ready: false,
    movement_counter: 0,
    pending_movement_acks: %{},
    tracked_entities: MapSet.new(),
    player_guids: [],
    mob_guids: [],
    gossip_menu_options: [],
    cell_activator: CellActivator
  ]

  def leave_world(%__MODULE__{} = state) do
    case state.player_tick_ref do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state = suspend_active_pet(state)

    if state.character, do: CharacterStore.put(state.character)

    if state.guid do
      leave_world_presence(state)
    end

    %__MODULE__{account: state.account, conn: state.conn}
  end

  def suspend_active_pet(%__MODULE__{character: %{unit: %{summon: pet_guid} = unit} = character} = state)
      when is_integer(pet_guid) and pet_guid > 0 do
    World.stop_entity(pet_guid)
    %{state | character: %{character | unit: %{unit | summon: 0}}}
  end

  def suspend_active_pet(%__MODULE__{} = state), do: state

  defp leave_world_presence(%__MODULE__{} = state) do
    ChatChannels.leave_all(state.guid)
    Entity.unregister(state.guid)
    AggroProbe.forget(state.guid)
    Metadata.delete(state.guid)
    SpatialHash.remove(:players, state.guid)
    state = Visibility.leave_player(state)

    case PartySystem.group_of(state.guid) do
      %Group{} = group -> Notifier.send_group_list(group)
      _ -> :ok
    end

    for guid <- state.player_guids, guid != state.guid do
      Entity.destroy_object(guid, state.guid)
    end

    :ok
  end
end
