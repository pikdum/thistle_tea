defmodule ThistleTea.Game.Entity.Logic.Engagement do
  @moduledoc """
  Canonical combat lifecycle transitions for mobs.

  Victim, threat, tap, combat flags, casting cancellation, and combat behavior
  memory change together here. Callers handle boundary concerns such as party
  lookup, EventAI callbacks, healing, and movement back to a spawn.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Threat

  @dynamic_flag_tapped 0x0004

  defmodule Tap do
    @moduledoc false
    @enforce_keys [:player]
    defstruct [:player, :group_id]
  end

  defmodule Result do
    @moduledoc false
    @enforce_keys [:entity, :from, :to, :reason]
    defstruct [:entity, :from, :to, :reason, :decision, :previous_victim, :victim, victim_changed?: false]
  end

  def enter(entity, target_guid, now, opts \\ [])

  def enter(%Mob{internal: %Internal{pet: %Pet{reaction_state: :passive}}} = entity, target_guid, now, opts) do
    if Keyword.get(opts, :allow_passive?, false) do
      enter_active(entity, target_guid, now, opts)
    else
      result(entity, entity, :passive)
    end
  end

  def enter(%Mob{unit: %Unit{health: health}} = entity, _target_guid, _now, _opts)
      when is_number(health) and health <= 0 do
    result(entity, entity, :dead)
  end

  def enter(%Mob{internal: %Internal{}} = entity, target_guid, now, opts)
      when is_integer(target_guid) and target_guid > 0 and is_integer(now) do
    enter_active(entity, target_guid, now, opts)
  end

  def enter(%Mob{} = entity, _target_guid, _now, _opts), do: result(entity, entity, :invalid_target)

  defp enter_active(%Mob{internal: %Internal{} = internal} = entity, target_guid, now, opts)
       when is_integer(target_guid) and target_guid > 0 and is_integer(now) do
    previous = entity
    entity = %{entity | internal: %{internal | in_combat: true, last_hostile_time: now}}
    entity = Threat.add(entity, target_guid, 0)

    %Result{entity: entity, decision: decision} =
      select_on_enter(entity, target_guid, Keyword.get(opts, :selection, []))

    entity = entity |> Combat.sync_combat_flag() |> mark_broadcast_update()
    result(previous, entity, :enter, decision)
  end

  def select(%Mob{} = entity, opts \\ []) do
    previous = entity

    case Threat.reselect(entity, opts) do
      {entity, {:switch, target_guid} = decision} ->
        entity = set_victim(entity, target_guid)
        result(previous, entity, :select, decision)

      {entity, decision} when decision in [:keep, :none] ->
        result(previous, entity, :select, decision)
    end
  end

  def drop(%Mob{} = entity, source_guid, opts \\ []) when is_integer(source_guid) do
    previous = entity

    if Threat.tracking?(entity, source_guid) do
      entity = Threat.remove(entity, source_guid)

      if Threat.entries(entity) == [] do
        result(previous, entity, :drop, :none)
      else
        %Result{entity: entity, decision: decision} = select(entity, opts)
        result(previous, entity, :drop, decision)
      end
    else
      result(previous, entity, :untracked, :keep)
    end
  end

  def leave(%Mob{} = entity, reason, opts \\ []) when is_atom(reason) do
    previous = entity
    clear_tap? = Keyword.get(opts, :clear_tap?, true)
    blackboard = Keyword.get(opts, :blackboard, entity.internal.blackboard)
    target = victim(entity)
    entity = Threat.wipe(entity)
    unit = clear_unit(entity.unit, clear_tap?)

    internal = %{
      entity.internal
      | in_combat: false,
        loot: clear_tap(entity.internal.loot, clear_tap?),
        blackboard: clear_combat_memory(blackboard)
    }

    entity =
      %{entity | unit: unit, internal: internal}
      |> Casting.cancel()
      |> Combat.sync_combat_flag()
      |> Effects.enqueue(leave_effects(entity.object.guid, target, clear_tap?))
      |> mark_broadcast_update()

    result(previous, entity, reason)
  end

  def die(%Mob{} = entity) do
    leave(entity, :death, clear_tap?: false)
  end

  def reset(%Mob{} = entity) do
    previous = entity
    unit = clear_unit(entity.unit, true)

    internal = %{
      entity.internal
      | in_combat: false,
        threat: %{},
        last_hostile_time: nil,
        loot: clear_tap(entity.internal.loot, true),
        blackboard: nil
    }

    entity = %{entity | unit: unit, internal: internal}
    result(previous, entity, :respawn)
  end

  def claim(%Mob{internal: %Internal{loot: %Loot{tapped_by: nil} = loot} = internal} = entity, %Tap{} = tap) do
    unit = %{entity.unit | dynamic_flags: Bitwise.bor(entity.unit.dynamic_flags || 0, @dynamic_flag_tapped)}
    internal = %{internal | loot: %{loot | tapped_by: tap}}

    %{entity | unit: unit, internal: internal}
    |> Effects.enqueue(Effects.tap_claimed(tap.player, tap.group_id))
    |> mark_broadcast_update()
  end

  def claim(%Mob{} = entity, %Tap{}), do: entity

  def focus(entity, target_guid, reason \\ :focus)

  def focus(%Mob{} = entity, target_guid, reason)
      when is_integer(target_guid) and target_guid > 0 and is_atom(reason) do
    previous = entity
    entity = set_victim(entity, target_guid)
    result(previous, entity, reason)
  end

  def focus(%Mob{} = entity, nil, reason) when is_atom(reason) do
    previous = entity
    target = victim(entity)
    entity = %{entity | unit: %{entity.unit | target: 0}}

    entity =
      if is_integer(target) do
        entity
        |> Effects.enqueue(Effects.attacker_lost(target))
        |> mark_broadcast_update()
      else
        entity
      end

    result(previous, entity, reason)
  end

  def phase(%Mob{internal: %Internal{in_combat: true}}), do: :engaged
  def phase(%Mob{unit: %Unit{health: health}}) when is_number(health) and health <= 0, do: :dead
  def phase(%Mob{}), do: :idle

  def victim(%Mob{unit: %Unit{target: target}}) when is_integer(target) and target > 0, do: target
  def victim(%Mob{}), do: nil

  defp set_victim(%Mob{} = entity, target_guid) do
    previous = victim(entity)

    if previous == target_guid do
      entity
    else
      blackboard = entity.internal.blackboard |> Blackboard.from_any() |> Blackboard.clear_attack_started()

      %{entity | unit: %{entity.unit | target: target_guid}, internal: %{entity.internal | blackboard: blackboard}}
      |> Effects.enqueue(victim_change_effects(previous, target_guid))
      |> mark_broadcast_update()
    end
  end

  defp select_on_enter(entity, target_guid, :target) do
    previous = entity
    entity = set_victim(entity, target_guid)
    result(previous, entity, :select, {:switch, target_guid})
  end

  defp select_on_enter(entity, _target_guid, opts) when is_list(opts), do: select(entity, opts)

  defp victim_change_effects(previous, target_guid) when is_integer(previous) do
    [Effects.attacker_lost(previous), Effects.attacker_gained(target_guid)]
  end

  defp victim_change_effects(_previous, target_guid), do: [Effects.attacker_gained(target_guid)]

  defp clear_unit(%Unit{} = unit, clear_tap?) do
    dynamic_flags =
      if clear_tap? do
        Bitwise.band(unit.dynamic_flags || 0, Bitwise.bnot(@dynamic_flag_tapped))
      else
        unit.dynamic_flags
      end

    %{unit | target: 0, dynamic_flags: dynamic_flags}
  end

  defp clear_tap(%Loot{} = loot, true), do: %{loot | tapped_by: nil}
  defp clear_tap(loot, _clear_tap?), do: loot

  defp clear_combat_memory(blackboard) do
    blackboard
    |> Blackboard.from_any()
    |> Blackboard.clear_chase()
    |> Blackboard.clear_attack()
    |> Blackboard.reset_spread()
    |> Blackboard.reset_spells()
    |> Blackboard.clear_flee()
  end

  defp leave_effects(source_guid, target, clear_tap?) do
    target_effects =
      if is_integer(target) do
        [Effects.attack_stop(source_guid, target), Effects.attacker_lost(target)]
      else
        []
      end

    if clear_tap?, do: target_effects ++ [Effects.tap_cleared()], else: target_effects
  end

  defp mark_broadcast_update(%Mob{internal: %Internal{} = internal} = entity) do
    %{entity | internal: %{internal | broadcast_update?: true}}
  end

  defp result(previous, entity, reason, decision \\ nil) do
    %Result{
      entity: entity,
      from: phase(previous),
      to: phase(entity),
      reason: reason,
      decision: decision,
      previous_victim: victim(previous),
      victim: victim(entity),
      victim_changed?: victim(previous) != victim(entity)
    }
  end
end
