defmodule ThistleTea.Game.Entity.Logic.ControlMovement do
  @moduledoc """
  Owns fear and confusion movement transitions, derived unit flags, and player
  control changes. Active auras select the behavior; blackboard memory retains
  only navigation progress and the movement mode to restore afterward.
  """

  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Confusion
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Fear
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Movement

  @confused_flag 0x00400000
  @fleeing_flag 0x00800000

  def active?(entity), do: mode(entity) != nil

  def mode(%{unit: %Unit{health: health}}) when is_number(health) and health <= 0, do: nil
  def mode(%{unit: %Unit{auras: holders}}), do: mode(holders)

  def mode(holders) when is_list(holders) do
    cond do
      has?(holders, :mod_confuse) -> :confusion
      feared?(holders) -> :fear
      true -> nil
    end
  end

  def mode(_entity), do: nil

  def reconcile(
        %{unit: %Unit{}, internal: %Internal{}, movement_block: %MovementBlock{}} = entity,
        previous,
        current,
        now
      ) do
    current_mode = mode(entity)
    entity = sync_flags(entity, current)
    previous_key = key(previous, mode(previous))
    current_key = key(current, current_mode)

    if previous_key == current_key do
      {entity, []}
    else
      {entity, movement_events} = transition(entity, current_mode, now)
      control_events = control_events(entity, previous_key != nil, current_key != nil)
      {entity, movement_events ++ control_events}
    end
  end

  def reconcile(entity, _previous, _current, _now), do: {entity, []}

  def restore(%Character{unit: %Unit{auras: holders}} = character, now) do
    {character, events} = reconcile(character, [], holders || [], now)
    Effects.enqueue(character, events)
  end

  def reset_navigation(%{internal: %Internal{} = internal} = entity) do
    blackboard = Blackboard.ensure(internal.blackboard)
    memory = blackboard.fear || blackboard.confusion
    running = if memory, do: memory.previous_running, else: internal.running
    blackboard = %{Blackboard.clear_move_target(blackboard) | fear: nil, confusion: nil}

    internal = %{
      internal
      | blackboard: blackboard,
        running: running,
        navigation_intents: [],
        events: Enum.reject(internal.events, &is_struct(&1, Effects.MonsterMove))
    }

    %{entity | internal: internal}
  end

  defp transition(entity, mode, now) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    memory = blackboard.fear || blackboard.confusion
    running = if memory, do: memory.previous_running, else: entity.internal.running
    {entity, events} = Movement.stop_with_effects(entity, now)
    blackboard = Blackboard.clear_move_target(blackboard)
    fear = if mode == :fear, do: %Fear{next_move_at: now, previous_running: running}
    confusion = confusion_memory(entity, mode, running, now)
    blackboard = %{blackboard | fear: fear, confusion: confusion}
    events_pending = Enum.reject(entity.internal.events, &is_struct(&1, Effects.MonsterMove))

    internal = %{
      entity.internal
      | blackboard: blackboard,
        running: running,
        navigation_intents: [],
        events: events_pending
    }

    {%{entity | internal: internal}, events}
  end

  defp confusion_memory(%{movement_block: %{position: {x, y, z, _}}}, :confusion, running, now),
    do: %Confusion{anchor: {x, y, z}, next_move_at: now, previous_running: running}

  defp confusion_memory(_entity, _mode, _running, _now), do: nil

  defp control_events(%Character{} = character, previous, current) when previous != current,
    do: [Effects.client_control_changed(not current and not match?(%{kind: :charm}, character.internal.possession))]

  defp control_events(%Mob{internal: %Internal{pet: %Pet{possessed?: true}}}, previous, current)
       when previous != current, do: [Effects.client_control_changed(not current)]

  defp control_events(_entity, _previous, _current), do: []

  defp sync_flags(%{unit: unit} = entity, holders) do
    flags = (unit.flags || 0) &&& bnot(@confused_flag ||| @fleeing_flag)
    alive? = not is_number(unit.health) or unit.health > 0
    flags = if alive? and has?(holders, :mod_confuse), do: flags ||| @confused_flag, else: flags
    fleeing? = feared?(holders) or (critter_fleeing?(entity) and not has?(holders, :prevent_fleeing))
    flags = if alive? and fleeing?, do: flags ||| @fleeing_flag, else: flags
    %{entity | unit: %{unit | flags: flags}}
  end

  def sync_flags(%{unit: %Unit{auras: holders}} = entity), do: sync_flags(entity, holders || [])

  defp critter_fleeing?(%{internal: %Internal{blackboard: %Blackboard{critter: memory} = blackboard}})
       when not is_nil(memory), do: Blackboard.fleeing?(blackboard)

  defp critter_fleeing?(_entity), do: false

  defp key(_holders, nil), do: nil

  defp key(holders, mode) do
    type = if mode == :fear, do: :mod_fear, else: :mod_confuse
    holder = Enum.find(holders, &Holder.has_aura_type?(&1, type))
    {mode, holder.spell.id, holder.caster_guid, holder.applied_at}
  end

  defp feared?(holders), do: has?(holders, :mod_fear) and not has?(holders, :prevent_fleeing)
  defp has?(holders, type), do: Enum.any?(holders, &Holder.has_aura_type?(&1, type))
end
