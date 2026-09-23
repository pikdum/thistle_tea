defmodule ThistleTea.Game.Entity.Logic.AI.Tick do
  @moduledoc """
  Next-tick policy for behavior-tree entities.

  Behavior status, aura upkeep, and regeneration each contribute a semantic
  deadline. Entity owners schedule the earliest deadline and use a default
  cadence only when no subsystem needs a specific wake.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.Combat
  alias ThistleTea.Game.Entity.Logic.AI.TickPlan
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Breathing
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.Intoxication
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.PetLoyalty
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.Rest
  alias ThistleTea.Game.Entity.Logic.TemporarySummon
  alias ThistleTea.Game.Spell.Cast

  @default_tick_ms 100

  def needs_tick?(%{internal: %Internal{casting: %Cast{}}}), do: true

  def needs_tick?(%{internal: %Internal{auto_shot: %{target_guid: target_guid}}})
      when is_integer(target_guid) and target_guid > 0, do: true

  def needs_tick?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
      when is_integer(target) and target > 0 do
    true
  end

  def needs_tick?(%{internal: %Internal{in_combat: true}}), do: true

  def needs_tick?(%{
        internal: %Internal{blackboard: %Blackboard{combat: %Combat{auto_attacking: true}}},
        unit: %Unit{target: target}
      })
      when is_integer(target) and target > 0 do
    true
  end

  def needs_tick?(%{unit: %Unit{auras: [_ | _]}}), do: true

  def needs_tick?(character),
    do:
      Breathing.needs_tick?(character) or Regen.needs_regen?(character) or Intoxication.needs_tick?(character) or
        Pvp.needs_tick?(character) or not is_nil(Rest.next_tick_at(character))

  def plan(entity, status, now) when is_integer(now) do
    TickPlan.new(now)
    |> schedule_status(status)
    |> schedule_extra_attacks(entity)
    |> schedule_aura(entity)
    |> schedule_regen(entity)
    |> schedule_pet_happiness(entity)
    |> schedule_pet_loyalty(entity)
    |> schedule_breathing(entity)
    |> schedule_sobering(entity)
    |> schedule_pvp(entity)
    |> schedule_rest(entity)
    |> schedule_summon_death(entity)
    |> schedule_movement(entity)
  end

  defp schedule_movement(plan, entity) do
    case Movement.completion_at(entity) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :movement, at)
      _ -> plan
    end
  end

  defp schedule_summon_death(plan, entity) do
    case TemporarySummon.next_at(entity, plan.now) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :summon_death, at)
      _ -> plan
    end
  end

  defp schedule_extra_attacks(plan, entity) do
    if ExtraAttacks.pending?(entity), do: TickPlan.schedule_in(plan, :extra_attacks, @default_tick_ms), else: plan
  end

  defp schedule_rest(plan, entity) do
    case Rest.next_tick_at(entity) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :rest, at)
      _ -> plan
    end
  end

  defp schedule_pvp(plan, entity) do
    if Pvp.needs_tick?(entity), do: TickPlan.schedule_in(plan, :pvp, 1_000), else: plan
  end

  defp schedule_pet_happiness(plan, entity) do
    case PetHappiness.next_tick_at(entity) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :pet_happiness, at)
      _ -> plan
    end
  end

  defp schedule_pet_loyalty(plan, entity) do
    case PetLoyalty.next_tick_at(entity) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :pet_loyalty, at)
      _ -> plan
    end
  end

  defp schedule_sobering(plan, entity) do
    if Intoxication.needs_tick?(entity) do
      TickPlan.schedule_at(plan, :sobering, entity.internal.next_sober_at || plan.now)
    else
      plan
    end
  end

  defp schedule_breathing(plan, entity) do
    if Breathing.needs_tick?(entity), do: TickPlan.schedule_in(plan, :breathing, 1_000), else: plan
  end

  def mob_delay(entity, status, now), do: entity |> plan(status, now) |> TickPlan.delay(@default_tick_ms)

  def player_delay(character, {:running, delay_ms}, now) when is_integer(delay_ms) and delay_ms > 0 do
    character |> plan({:running, delay_ms}, now) |> TickPlan.delay(@default_tick_ms)
  end

  def player_delay(character, {:running, delay_ms, _reason}, now) when is_integer(delay_ms) and delay_ms > 0 do
    player_delay(character, {:running, delay_ms}, now)
  end

  def player_delay(character, _status, now) do
    character |> plan(:running, now) |> TickPlan.delay(@default_tick_ms)
  end

  defp schedule_status(plan, {:running, delay_ms, reason}) when is_integer(delay_ms) and delay_ms >= 0 do
    TickPlan.schedule_in(plan, reason, delay_ms)
  end

  defp schedule_status(plan, {:running, delay_ms}) when is_integer(delay_ms) and delay_ms >= 0 do
    TickPlan.schedule_in(plan, :behavior, delay_ms)
  end

  defp schedule_status(plan, _status), do: plan

  defp schedule_aura(plan, %{unit: %Unit{auras: [_ | _]}} = entity) do
    case Aura.next_event_at(entity) do
      at when is_integer(at) -> TickPlan.schedule_at(plan, :aura, at)
      _ -> plan
    end
  end

  defp schedule_aura(plan, _entity), do: plan

  defp schedule_regen(plan, %{internal: %Internal{blackboard: blackboard}} = entity) do
    blackboard = Blackboard.ensure(blackboard)

    plan
    |> schedule_resource_regen(entity, blackboard)
    |> schedule_focus_regen(entity, blackboard)
  end

  defp schedule_regen(plan, _entity), do: plan

  defp schedule_resource_regen(plan, entity, blackboard) do
    if Regen.needs_resource_regen?(entity) do
      delay_ms = Blackboard.delay_until(blackboard, :next_regen_at, plan.now)
      TickPlan.schedule_in(plan, :regen, delay_ms)
    else
      plan
    end
  end

  defp schedule_focus_regen(plan, entity, blackboard) do
    if Regen.needs_focus_regen?(entity) do
      delay_ms = Blackboard.delay_until(blackboard, :next_focus_regen_at, plan.now)
      TickPlan.schedule_in(plan, :focus_regen, delay_ms)
    else
      plan
    end
  end
end
