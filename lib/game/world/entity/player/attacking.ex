defmodule ThistleTea.Game.World.Entity.Player.Attacking do
  @moduledoc "Validates player melee targets and starts the shared attack behavior."
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.TargetRef
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Player.TickScheduler
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  require Logger

  def start_selected(%{target: guid, character: %Character{} = character} = state, %TargetRef{guid: guid} = target) do
    metadata = Metadata.query(guid, [:alive?, :incarnation_id]) || %{}

    if not Entity.dead?(character) and TargetRef.active?(target, metadata), do: start(state, guid), else: state
  end

  def start_selected(state, %TargetRef{}), do: state

  def start(%{character: character} = state, target_guid) do
    Logger.info("Starting melee attack: #{target_guid}")

    if valid_attack_target?(state, target_guid) do
      target_ref = TargetRef.new(target_guid, Metadata.query(target_guid, [:incarnation_id]) || %{})

      {character, events} = PlayerCombat.start_melee_attack(character, target_ref)
      context = Context.new(self())
      character = character |> EventSink.emit(events, context) |> EventSink.emit_pending(context)

      UpdateObject.from_entity(character, :values)
      |> World.broadcast_packet(character)

      state
      |> Map.put(:character, character)
      |> TickScheduler.schedule_now()
    else
      send_attack_stop(state, target_guid)
    end
  end

  def stop(%{character: %Character{} = character} = state) do
    {character, events} = PlayerCombat.stop_melee_attack(character)
    context = Context.new(self())
    character = character |> EventSink.emit(events, context) |> EventSink.emit_pending(context)

    character |> UpdateObject.from_entity(:values) |> World.broadcast_packet(character)

    case Map.get(state, :player_tick_ref) do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    state
    |> Map.put(:character, character)
    |> Map.put(:player_tick_ref, nil)
    |> TickScheduler.ensure_scheduled()
  end

  def stop(state), do: state

  defp valid_attack_target?(
         %{guid: guid, character: %Character{internal: %{world: world}} = character} = state,
         target_guid
       )
       when is_integer(target_guid) and target_guid > 0 do
    target_guid != guid and
      match?({^world, _x, _y, _z}, World.position(target_guid)) and
      unit_target?(target_guid) and
      Visibility.can_see?(state, target_guid) and
      Hostility.attackable?(character, target_guid)
  end

  defp valid_attack_target?(_state, _target_guid), do: false

  defp unit_target?(target_guid) when is_integer(target_guid), do: Guid.entity_type(target_guid) in [:player, :mob]

  defp send_attack_stop(%{guid: guid} = state, target_guid) when is_integer(guid) do
    enemy = if is_integer(target_guid) and target_guid > 0, do: target_guid, else: 0
    Network.send_packet(%Message.SmsgAttackstop{player: guid, enemy: enemy})
    state
  end

  defp send_attack_stop(state, _target_guid), do: state
end
