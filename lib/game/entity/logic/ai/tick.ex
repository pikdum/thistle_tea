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
  alias ThistleTea.Game.Entity.Logic.Regen
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

  def needs_tick?(character), do: Regen.needs_regen?(character)

  def plan(entity, status, now) when is_integer(now) do
    TickPlan.new(now)
    |> schedule_status(status)
    |> schedule_aura(entity)
    |> schedule_regen(entity)
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
    if Regen.needs_regen?(entity) do
      delay_ms = Blackboard.delay_until(Blackboard.ensure(blackboard), :next_regen_at, plan.now)
      TickPlan.schedule_in(plan, :regen, delay_ms)
    else
      plan
    end
  end

  defp schedule_regen(plan, _entity), do: plan
end
