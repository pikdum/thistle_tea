defmodule ThistleTea.Game.Player.Movement do
  @moduledoc """
  Translates client movement events into character movement rules.
  """
  use ThistleTea.Game.Network.Opcodes, [:MSG_MOVE_FALL_LAND, :MSG_MOVE_START_SWIM]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.MovementHandoff
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Exploration, as: PlayerExploration
  alias ThistleTea.Game.Player.Rest, as: PlayerRest
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.AggroProbe
  alias ThistleTea.Game.World.ChaseWatch
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Pathfinding
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Transports
  alias ThistleTea.Game.World.Visibility

  @spell_failed_moving 0x2E
  @stuck_spell 7355
  @client_projection_ms 750

  def handle(%Message.MsgMove{} = message, %{character: %Character{} = character} = state) do
    if accepts_input?(character), do: handle_movement(message, state), else: state
  end

  def handle(%Message.MsgMove{} = message, state), do: handle_movement(message, state)

  defp handle_movement(%Message.MsgMove{}, %{character: %Character{internal: %{taxi_flight: %Flight{}}}} = state),
    do: state

  defp handle_movement(%Message.MsgMove{}, %{server_movement: server_movement} = state)
       when not is_nil(server_movement), do: state

  defp handle_movement(
         %Message.MsgMove{payload: payload, opcode: opcode},
         %{ready: true, guid: player_guid, active_mover_guid: mover_guid, character: %Character{} = character} = state
       )
       when is_integer(mover_guid) and mover_guid > 0 and mover_guid != player_guid do
    if Companion.possession_guid(character) == mover_guid do
      case Entity.pid(mover_guid) do
        pid when is_pid(pid) -> send(pid, {:controlled_move, player_guid, payload, opcode})
        _ -> nil
      end
    end

    state
  end

  defp handle_movement(
         %Message.MsgMove{} = message,
         %{
           ready: true,
           guid: player_guid,
           active_mover_guid: mover_guid,
           character: %Character{movement_block: %MovementBlock{} = movement_block, unit: %Unit{}} = character
         } = state
       )
       when mover_guid in [nil, player_guid] do
    if is_integer(Companion.possession_guid(character)) do
      state
    else
      reconcile_movement(message, state, movement_block)
    end
  end

  defp handle_movement(_message, state), do: state

  def handle_controlled(%{character: %Character{} = character, server_movement: nil} = state, caster, payload, opcode) do
    if PlayerPossession.controlled_by?(character, caster) and can_move?(character) do
      message = %Message.MsgMove{payload: payload, opcode: opcode}
      reconcile_movement(message, state, character.movement_block, controller: caster)
    else
      state
    end
  end

  def handle_controlled(state, _caster, _payload, _opcode), do: state

  def finish_input(
        %{ready: true, server_movement: nil, character: %Character{} = character} = state,
        controller,
        payload
      ) do
    case MovementHandoff.take(character, controller, Time.now()) do
      {:ok, character} ->
        message = Message.MsgMove.from_final_movement(payload)
        opts = [controller: controller, final?: true]
        reconcile_movement(message, %{state | character: character}, character.movement_block, opts)

      {:error, character} ->
        %{state | character: character}
    end
  end

  def finish_input(state, _controller, _payload), do: state

  defp reconcile_movement(message, state, movement_block, opts \\ []) do
    character = state.character
    movement_block = MovementBlock.from_binary(message.payload, movement_block)

    case Transports.reconcile(character, movement_block) do
      {:ok, movement_block} ->
        state = MovementControl.track_transport_boarding(state, character.movement_block, movement_block)
        handle_player_movement(message, state, movement_block, opts)

      {:error, _reason} ->
        state
    end
  end

  def accepts_input?(%Character{} = character), do: not PlayerPossession.active?(character) and can_move?(character)
  def accepts_input?(_character), do: true

  defp can_move?(%Character{internal: %Internal{movement_start_time: started}}) when is_integer(started), do: false
  defp can_move?(%Character{internal: %Internal{logout: :rooted}}), do: false
  defp can_move?(%Character{} = character), do: not Core.dead?(character) and not ControlMovement.active?(character)

  def apply_environment(%Character{} = character, opcode, now) do
    character
    |> Falling.update(action(opcode), now)
    |> Breathing.update(
      liquid_surface(character),
      now,
      :rand.uniform(max(character.unit.level || 1, 1)) - 1,
      body_height(character)
    )
  end

  def interrupt_attacks(character, false, _now), do: character
  def interrupt_attacks(character, true, now), do: AutoRepeat.interrupt(character, now)

  def body_height(%Character{} = character), do: ModelGeometry.height(character.unit.display_id)
  def body_height(_entity), do: 2.0

  def liquid_surface(%Character{} = character) do
    {x, y, z, _} = character.movement_block.position
    Pathfinding.query_liquid_surface(character.internal.world.map_id, {x, y, z})
  end

  def publish_changes(%{character: %Character{} = character} = state) do
    state =
      if character.internal.broadcast_update? do
        PlayerServer.maybe_broadcast_update(state)
      else
        %{state | character: EventSink.emit_pending(character)}
      end

    TickScheduler.ensure_scheduled(state)
  end

  def publish_changes(state), do: state

  defp action(@msg_move_fall_land), do: :land
  defp action(@msg_move_start_swim), do: :swim
  defp action(_opcode), do: :move

  defp handle_player_movement(
         message,
         %{character: %Character{movement_block: %MovementBlock{} = previous_movement_block}} = state,
         %MovementBlock{} = movement_block,
         opts
       ) do
    character = MovementHandoff.clear(state.character)
    character = %{character | movement_block: movement_block} |> remember_safe_position()
    %{internal: %{world: world}} = character
    %MovementBlock{position: {x1, y1, z1, orientation}} = movement_block
    now = Time.now()
    movement_velocity = MovementBlock.client_velocity(movement_block)

    position_changed? = MovementBlock.position_changed?(previous_movement_block, movement_block)
    translating? = MovementBlock.translating?(movement_block)

    presence_metadata = %{
      orientation: orientation,
      movement_velocity: movement_velocity,
      airborne?: MovementBlock.airborne?(movement_block),
      last_move_at: now,
      moving_until: if(translating?, do: now + @client_projection_ms, else: now)
    }

    moved? = position_changed? or translating?
    moving_or_turning? = moved? or Bitwise.band(movement_block.movement_flags || 0, 0x3F) != 0
    character = Emote.move(character, moved?, moving_or_turning?, now)
    character = apply_environment(character, message.opcode, now)
    character = interrupt_attacks(character, moved? or MovementBlock.airborne?(movement_block), now)
    character = interrupt_auras(character, moved?)
    character = interrupt_water_auras(character, movement_block, state.character.movement_block)

    Presence.relocate_client(
      character,
      presence_metadata,
      movement_velocity,
      now,
      @client_projection_ms
    )

    new_state =
      if moved? do
        AggroProbe.notify_player_moved(state.guid, world, {x1, y1, z1})
        ChaseWatch.notify_moved(state.guid, {x1, y1, z1})

        %{state | character: character}
        |> cancel_moving_cast(movement_block, Keyword.get(opts, :final?, false))
        |> PlayerRest.check_tavern_exit()
        |> PlayerExploration.check_movement(now)
      else
        %{state | character: character}
      end

    new_state
    |> Visibility.refresh_player()
    |> broadcast(message, Keyword.get(opts, :controller))
    |> publish_changes()
  end

  defp remember_safe_position(%Character{} = character) do
    if SafePosition.needs_update?(character) do
      {x, y, _z, _orientation} = character.movement_block.position
      heights = Pathfinding.find_heights(character.internal.world.map_id, {x, y})
      SafePosition.remember(character, heights)
    else
      character
    end
  end

  defp cancel_moving_cast(state, _movement, true), do: state

  defp cancel_moving_cast(
         %{character: %Character{internal: %Internal{casting: %Cast{spell: %Spell{id: @stuck_spell}}}}} = state,
         movement,
         false
       ) do
    if MovementBlock.falling_far?(movement), do: state, else: Spellcasting.cancel(state, @spell_failed_moving)
  end

  defp cancel_moving_cast(state, _movement, false), do: Spellcasting.cancel(state, @spell_failed_moving)

  defp broadcast(state, message, controller) do
    recipients =
      if is_integer(controller),
        do: Enum.uniq([state.guid | Map.get(state, :player_guids, [])]) |> List.delete(controller),
        else: Map.get(state, :player_guids)

    Message.MsgMove.to_packet(state.guid, message.payload, message.opcode)
    |> World.broadcast_packet(state.character, include_self?: is_integer(controller), recipients: recipients)

    state
  end

  defp interrupt_auras(character, position_changed?) do
    mask = if position_changed?, do: AuraLogic.interrupt_mask(:move), else: AuraLogic.interrupt_mask(:turn)
    auras_before = character.unit.auras
    {character, events} = AuraLogic.remove_with_interrupt_flags(character, mask, Time.now())

    character =
      character
      |> Effects.enqueue(events)
      |> EventSink.emit_pending()

    if character.unit.auras != auras_before do
      %UpdateObject{update_type: :values, object_type: :player}
      |> struct(Map.from_struct(character))
      |> World.broadcast_packet(character)
    end

    character
  end

  defp interrupt_water_auras(character, current, previous) do
    if MovementBlock.swimming?(previous) == MovementBlock.swimming?(current) do
      character
    else
      action = if MovementBlock.swimming?(current), do: :under_water, else: :above_water

      {character, events} =
        AuraLogic.remove_with_interrupt_flags(character, AuraLogic.interrupt_mask(action), Time.now())

      character |> Effects.enqueue(events) |> EventSink.emit_pending()
    end
  end
end
