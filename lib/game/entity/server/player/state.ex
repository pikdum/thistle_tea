defmodule ThistleTea.Game.Entity.Server.Player.State do
  @moduledoc """
  Runtime state owned by a logged-in player entity.

  It contains the character and the boundary bookkeeping required to interpret
  that character's effects. `leave_world/1` tears down that world presence.
  """
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.Script.Run, as: ScriptRun
  alias ThistleTea.Game.Entity.Logic.Aura.SingleTarget
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Dueling
  alias ThistleTea.Game.Entity.Logic.MovementHandoff
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Entity.Server.GuardianOwner
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.MiniPetOwner
  alias ThistleTea.Game.Entity.Server.Player.PossessionOwner
  alias ThistleTea.Game.Entity.Server.Player.ServerMovement
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Notifier
  alias ThistleTea.Game.Player.Buyback
  alias ThistleTea.Game.Player.Guilds
  alias ThistleTea.Game.Player.Instances
  alias ThistleTea.Game.Player.ItemDurations
  alias ThistleTea.Game.Player.Logout
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.OutdoorPvp
  alias ThistleTea.Game.Player.QuestSharing
  alias ThistleTea.Game.Player.Rest
  alias ThistleTea.Game.Player.Resurrection
  alias ThistleTea.Game.Player.Taxi
  alias ThistleTea.Game.Player.Weather
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.PostOffice
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.World.System.ChatChannels
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.System.Trade, as: TradeSystem
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  defstruct [
    :connection_pid,
    :account,
    :guid,
    :packed_guid,
    :character,
    :equipment_requirements,
    :spell_area_snapshot,
    :visibility_cells,
    :viewpoint_guid,
    :stealth_detection_ref,
    :player_tick_ref,
    :logout_timer,
    :target,
    :loot_guid,
    :loot_type,
    :pending_repop,
    :next_exploration_check_at,
    :mail_session_token,
    :mail_delivery_ref,
    :pending_last_instance_map,
    :transport_refresh_pending,
    :taxi_arrival_ref,
    :server_movement,
    :active_mover_guid,
    :client_mover_guid,
    :active_banker_guid,
    :gossip_menu_guid,
    :companion_monitor,
    :possession_monitor,
    :mini_pet_monitor,
    :pet_unlearn_offer,
    :talent_reset_offer,
    :quest_share,
    :quest_share_monitor,
    :item_duration_timer,
    :instance_eviction,
    :weather_key,
    :weather_token,
    :outdoor_pvp_key,
    :outdoor_pvp_token,
    :outdoor_pvp_tower_buff,
    outdoor_pvp_favor?: false,
    item_durations_active?: false,
    ready: false,
    pending_worldport?: false,
    movement_counter: 0,
    pending_movement_acks: %{},
    tracked_entities: MapSet.new(),
    quest_object_flags: %{},
    questgiver_statuses: %{},
    player_guids: [],
    mob_guids: [],
    gossip_menu_options: [],
    cell_activator: CellActivator,
    guardian_monitors: %{}
  ]

  def prepare_worldport(%__MODULE__{} = state, origin, destination) do
    state
    |> clear_scripts()
    |> detach_single_target_auras()
    |> Weather.leave()
    |> Resurrection.cancel_transfer()
    |> Instances.clear()
    |> MiniPetOwner.dismiss()
    |> dismiss_guardians()
    |> dismiss_totems()
    |> do_prepare_worldport(origin, destination)
  end

  defp do_prepare_worldport(%__MODULE__{} = state, %WorldRef{map_id: map_id, instance_id: instance_id}, %WorldRef{
         instance_id: nil
       })
       when is_integer(instance_id) do
    %{state | pending_last_instance_map: map_id, active_banker_guid: nil, pending_repop: nil, pending_worldport?: true}
  end

  defp do_prepare_worldport(%__MODULE__{} = state, %WorldRef{}, %WorldRef{}) do
    %{state | pending_last_instance_map: nil, active_banker_guid: nil, pending_repop: nil, pending_worldport?: true}
  end

  def complete_worldport(%__MODULE__{pending_last_instance_map: map_id} = state) when is_integer(map_id) do
    Network.send_packet(%Message.SmsgUpdateLastInstance{map: map_id})
    %{state | pending_last_instance_map: nil, pending_worldport?: false}
  end

  def complete_worldport(%__MODULE__{} = state), do: %{state | pending_worldport?: false}

  def leave_world(%__MODULE__{} = state) do
    state = state |> clear_scripts() |> Logout.clear() |> Instances.clear() |> Resurrection.clear()

    case state.player_tick_ref do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state =
      if state.guid && state.character do
        TradeSystem.cancel(state.guid)
        DuelSystem.disconnect(state.guid)
        %{state | character: Dueling.abandon(state.character, Time.now())}
      else
        state
      end

    state = state |> Looting.release() |> QuestSharing.disconnect() |> OutdoorPvp.leave() |> Weather.leave()
    state = state |> PossessionOwner.release() |> disengage() |> detach_single_target_auras()
    state = CompanionOwner.suspend(state)
    state = MiniPetOwner.dismiss(state)
    state = dismiss_guardians(state)
    state = Taxi.disconnect(state)
    state = ServerMovement.cancel(state)
    state = leave_transport(state)

    state = close_mailbox(state)
    state = Buyback.logout(state)
    state = ItemDurations.logout(state)

    if state.guid && state.character do
      BattlegroundSystem.disconnect(state.guid, state.character.movement_block.position)
    end

    if state.character, do: CharacterStore.put(Rest.logout(state).character)

    if state.guid do
      Guilds.signed_off(state)
      leave_world_presence(state)
    end

    %__MODULE__{account: state.account, connection_pid: state.connection_pid}
  end

  defp disengage(%__MODULE__{character: %Character{} = character} = state) do
    character = character |> Casting.cancel() |> MovementHandoff.clear()
    {character, effects} = PlayerCombat.disengage(character)
    character = character |> Totems.dismiss_all() |> EventSink.emit_pending()
    %{state | character: EventSink.emit(character, effects)}
  end

  defp disengage(%__MODULE__{} = state), do: state

  defp clear_scripts(%__MODULE__{character: %Character{} = character} = state),
    do: %{state | character: ScriptRun.clear(character)}

  defp clear_scripts(%__MODULE__{} = state), do: state

  defp detach_single_target_auras(%__MODULE__{character: %Character{} = character} = state) do
    character = character |> SingleTarget.detach(Time.now()) |> EventSink.emit_pending()
    %{state | character: character}
  end

  defp detach_single_target_auras(%__MODULE__{} = state), do: state

  defp dismiss_totems(%__MODULE__{character: nil} = state), do: state

  defp dismiss_totems(%__MODULE__{} = state) do
    %{state | character: state.character |> Totems.dismiss_all() |> EventSink.emit_pending()}
  end

  defp dismiss_guardians(%__MODULE__{character: nil} = state), do: state

  defp dismiss_guardians(%__MODULE__{} = state) do
    {character, monitors} = GuardianOwner.dismiss(state.character, state.guardian_monitors)
    %{state | character: character, guardian_monitors: monitors}
  end

  defp leave_transport(%__MODULE__{character: %Character{} = character} = state) do
    Transports.leave(character)
    character = %{character | movement_block: MovementBlock.clear_transport(character.movement_block)}
    %{state | character: character}
  end

  defp leave_transport(%__MODULE__{} = state), do: state

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
    Presence.leave(state.character)
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
