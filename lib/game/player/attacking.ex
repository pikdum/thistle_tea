defmodule ThistleTea.Game.Player.Attacking do
  @moduledoc "Validates player melee targets and starts the shared attack behavior."
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Entity.Server.Player.TickScheduler
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility

  require Logger

  def start_selected(%{target: guid, character: %Character{} = character} = state, %TargetRef{guid: guid} = target) do
    metadata = Metadata.query(guid, [:alive?, :incarnation_id]) || %{}

    if not Core.dead?(character) and TargetRef.active?(target, metadata), do: start(state, guid), else: state
  end

  def start_selected(state, %TargetRef{}), do: state

  def start(%{character: character} = state, target_guid) do
    Logger.info("Starting melee attack: #{target_guid}")

    if valid_attack_target?(state, target_guid) do
      target_ref = TargetRef.new(target_guid, Metadata.query(target_guid, [:incarnation_id]) || %{})

      character =
        character
        |> maybe_reset_attack_started(target_guid)
        |> set_attack_target(target_guid)
        |> BT.enable_auto_attack(target_ref)

      Core.update_object(character, :values)
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

    character |> Core.update_object(:values) |> World.broadcast_packet(character)

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

  defp maybe_reset_attack_started(%Character{unit: %Unit{target: target}} = character, target_guid)
       when is_integer(target_guid) do
    if target == target_guid do
      character
    else
      BT.reset_attack_started(character)
    end
  end

  defp maybe_reset_attack_started(character, _target_guid), do: character

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

  defp set_attack_target(%Character{unit: unit} = character, target_guid) when is_integer(target_guid) do
    %{character | unit: %{unit | target: target_guid}}
  end

  defp set_attack_target(character, _target_guid), do: character
end
