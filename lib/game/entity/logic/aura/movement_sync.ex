defmodule ThistleTea.Game.Entity.Logic.Aura.MovementSync do
  @moduledoc """
  Reconciles movement state with the current aura set after any aura change:
  root/stun halting and flags, the safe-fall/hover/water-walk movement flags,
  the stunned unit flag, recomputed speeds, and the client events announcing
  each change.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.MovementStats

  @movement_flag_root 0x08000000
  @movement_flag_safe_fall 0x20000000
  @movement_flag_water_walk 0x10000000
  @movement_flag_hover 0x40000000

  @unit_flag_stunned 0x00040000

  def sync_movement_state(entity, now) do
    old_run_speed = run_speed(entity)
    entity = MovementStats.recompute(entity)
    {entity, events} = sync_movement_flags(entity, now)
    {entity, feather_events} = sync_movement_flag_aura(entity, :feather_fall, @movement_flag_safe_fall)
    {entity, hover_events} = sync_movement_flag_aura(entity, :hover, @movement_flag_hover)
    {entity, water_walk_events} = sync_movement_flag_aura(entity, :water_walk, @movement_flag_water_walk)
    entity = sync_stunned_flag(entity)
    flag_events = feather_events ++ hover_events ++ water_walk_events
    {entity, speed_change_events(entity, old_run_speed) ++ events ++ flag_events}
  end

  defp sync_movement_flags(%{movement_block: %MovementBlock{} = mb, unit: %Unit{auras: holders}} = entity, now) do
    flags = mb.movement_flags || 0
    was_rooted? = rooted?(entity)
    has_root? = Enum.any?(holders, &(Holder.has_aura_type?(&1, :mod_root) or Holder.has_aura_type?(&1, :mod_stun)))

    new_flags =
      if has_root?,
        do: flags ||| @movement_flag_root,
        else: flags &&& bnot(@movement_flag_root)

    entity = %{entity | movement_block: %{mb | movement_flags: new_flags}}
    entity = put_rooted(entity, has_root?)
    root_events = if has_root? == was_rooted?, do: [], else: [Event.movement_root_changed(has_root?)]

    if has_root? and not was_rooted? do
      {Movement.halt(entity, now), [Event.movement_stopped() | root_events]}
    else
      {entity, root_events}
    end
  end

  defp sync_movement_flags(entity, _now), do: {entity, []}

  defp rooted?(%{internal: internal}) when is_struct(internal), do: Map.get(internal, :rooted?) == true
  defp rooted?(_entity), do: false

  defp put_rooted(%{internal: internal} = entity, rooted?) when is_struct(internal) do
    %{entity | internal: Map.put(internal, :rooted?, rooted?)}
  end

  defp put_rooted(entity, _rooted?), do: entity

  defp sync_movement_flag_aura(
         %{movement_block: %MovementBlock{} = mb, unit: %Unit{auras: holders}} = entity,
         type,
         bit
       )
       when is_list(holders) do
    flags = mb.movement_flags || 0
    was_on? = (flags &&& bit) != 0
    has_aura? = Enum.any?(holders, &Holder.has_aura_type?(&1, type))

    new_flags =
      if has_aura?,
        do: flags ||| bit,
        else: flags &&& bnot(bit)

    entity = %{entity | movement_block: %{mb | movement_flags: new_flags}}

    if has_aura? == was_on? do
      {entity, []}
    else
      {entity, [movement_flag_event(type, has_aura?)]}
    end
  end

  defp sync_movement_flag_aura(entity, _type, _bit), do: {entity, []}

  defp movement_flag_event(:feather_fall, enabled?), do: Event.feather_fall_changed(enabled?)
  defp movement_flag_event(:hover, enabled?), do: Event.hover_changed(enabled?)
  defp movement_flag_event(:water_walk, enabled?), do: Event.water_walk_changed(enabled?)

  defp sync_stunned_flag(%{unit: %Unit{auras: holders} = unit} = entity) when is_list(holders) do
    flags = unit.flags || 0
    stunned? = Enum.any?(holders, &Holder.has_aura_type?(&1, :mod_stun))

    new_flags =
      if stunned?,
        do: flags ||| @unit_flag_stunned,
        else: flags &&& bnot(@unit_flag_stunned)

    %{entity | unit: %{unit | flags: new_flags}}
  end

  defp sync_stunned_flag(entity), do: entity

  defp speed_change_events(entity, old_run_speed) do
    new_run_speed = run_speed(entity)

    if is_number(old_run_speed) and is_number(new_run_speed) and old_run_speed != new_run_speed do
      [Event.movement_speed_changed(new_run_speed)]
    else
      []
    end
  end

  defp run_speed(%{movement_block: %MovementBlock{run_speed: run_speed}}), do: run_speed
  defp run_speed(_entity), do: nil
end
