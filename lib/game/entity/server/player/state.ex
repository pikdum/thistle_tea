defmodule ThistleTea.Game.Entity.Server.Player.State do
  @moduledoc """
  Runtime state owned by a logged-in player entity.

  It contains the character and the boundary bookkeeping required to interpret
  that character's effects. `leave_world/1` tears down that world presence.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion, as: CompanionData
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.ChatChannels
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  defstruct [
    :connection_pid,
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
    :mail_session_token,
    :mail_delivery_ref,
    :pending_last_instance_map,
    :active_mover_guid,
    ready: false,
    movement_counter: 0,
    pending_movement_acks: %{},
    tracked_entities: MapSet.new(),
    player_guids: [],
    mob_guids: [],
    gossip_menu_options: [],
    cell_activator: CellActivator
  ]

  def prepare_worldport(%__MODULE__{} = state, %WorldRef{map_id: map_id, instance_id: instance_id}, %WorldRef{
        instance_id: nil
      })
      when is_integer(instance_id) do
    %{state | pending_last_instance_map: map_id}
  end

  def prepare_worldport(%__MODULE__{} = state, %WorldRef{}, %WorldRef{}) do
    %{state | pending_last_instance_map: nil}
  end

  def complete_worldport(%__MODULE__{pending_last_instance_map: map_id} = state) when is_integer(map_id) do
    Network.send_packet(%Message.SmsgUpdateLastInstance{map: map_id})
    %{state | pending_last_instance_map: nil}
  end

  def complete_worldport(%__MODULE__{} = state), do: state

  def leave_world(%__MODULE__{} = state) do
    case state.player_tick_ref do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state =
      if state.guid && state.character do
        DuelSystem.disconnect(state.guid)
        %{state | character: Dueling.abandon(state.character, Time.now())}
      else
        state
      end

    state = suspend_companion(state)

    state = close_mailbox(state)

    if state.character, do: CharacterStore.put(state.character)

    if state.guid do
      leave_world_presence(state)
    end

    %__MODULE__{account: state.account, connection_pid: state.connection_pid}
  end

  def suspend_companion(%__MODULE__{character: %Character{} = character} = state) do
    case Companion.relationship(character) do
      %CompanionData{kind: kind, status: {:active, %EntityRef{guid: guid}}}
      when kind in [:hunter_pet, :guardian] ->
        World.stop_entity(guid)
        %{state | character: Companion.suspend(character)}

      %CompanionData{status: {:active, %EntityRef{guid: guid, spell_id: spell_id}}} ->
        case Entity.pid(guid) do
          pid when is_pid(pid) -> send(pid, {:release_control, state.guid, spell_id})
          _ -> :ok
        end

        %{state | character: Companion.clear(character)}

      _ ->
        state
    end
  end

  def suspend_companion(%__MODULE__{} = state), do: state

  defp close_mailbox(
         %__MODULE__{
           guid: guid,
           mail_session_token: token,
           character: %{internal: %{mailbox: mailbox} = internal} = character
         } = state
       )
       when is_integer(guid) and is_reference(token) do
    if is_reference(state.mail_delivery_ref), do: Process.cancel_timer(state.mail_delivery_ref)

    case PostOffice.close(guid, token, mailbox) do
      :ok -> %{state | character: %{character | internal: %{internal | mailbox: []}}, mail_delivery_ref: nil}
      {:error, _reason} -> %{state | mail_delivery_ref: nil}
    end
  end

  defp close_mailbox(%__MODULE__{} = state), do: state

  defp leave_world_presence(%__MODULE__{} = state) do
    InstanceSystem.leave(state.guid, state.character.internal.world)
    ChatChannels.leave_all(state.guid)
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
