defmodule ThistleTea.Game.Entity.Logic.AI.Tick do
  @moduledoc """
  Next-tick policy for behavior-tree entities: whether a player needs ticking
  at all, and how long to sleep before the next tick. Both variants honor
  `{:running, delay_ms}` self-pacing from the tree; the player variant adds
  passive aura/regen wake-up heuristics. A running status may include a wake
  reason as its third tuple element.
  """
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Spell.Cast

  @default_tick_ms 100

  def needs_tick?(%{internal: %Internal{casting: %Cast{}}}), do: true

  def needs_tick?(%{internal: %Internal{in_combat: true}, unit: %Unit{target: target}})
      when is_integer(target) and target > 0 do
    true
  end

  def needs_tick?(%{internal: %Internal{in_combat: true}}), do: true

  def needs_tick?(%{internal: %Internal{blackboard: %Blackboard{auto_attacking: true}}, unit: %Unit{target: target}})
      when is_integer(target) and target > 0 do
    true
  end

  def needs_tick?(%{unit: %Unit{auras: [_ | _]}}), do: true

  def needs_tick?(character), do: Regen.needs_regen?(character)

  def mob_delay({:running, delay_ms}) when is_integer(delay_ms) and delay_ms >= 0 do
    delay_ms
  end

  def mob_delay({:running, delay_ms, _reason}) when is_integer(delay_ms) and delay_ms >= 0 do
    delay_ms
  end

  def mob_delay(_status), do: @default_tick_ms

  def player_delay(character, {:running, delay_ms}, now) when is_integer(delay_ms) and delay_ms > 0 do
    case regen_delay(character, now) do
      regen_delay when is_integer(regen_delay) -> min(delay_ms, regen_delay)
      _ -> delay_ms
    end
  end

  def player_delay(character, {:running, delay_ms, _reason}, now) when is_integer(delay_ms) and delay_ms > 0 do
    player_delay(character, {:running, delay_ms}, now)
  end

  def player_delay(character, _status, now) do
    if passive?(character) do
      passive_delay(character, now)
    else
      @default_tick_ms
    end
  end

  defp passive_delay(character, now) do
    [aura_delay(character, now), regen_delay(character, now)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> @default_tick_ms
      delays -> delays |> Enum.min() |> max(0)
    end
  end

  defp aura_delay(%{unit: %Unit{auras: [_ | _]}} = character, now) do
    case Aura.next_event_at(character) do
      at when is_integer(at) -> max(at - now, 0)
      _ -> @default_tick_ms
    end
  end

  defp aura_delay(_character, _now), do: nil

  defp regen_delay(%{internal: %Internal{blackboard: blackboard}} = character, now) do
    if Regen.needs_regen?(character) do
      Blackboard.delay_until(Blackboard.from_any(blackboard), :next_regen_at, now)
    end
  end

  defp regen_delay(_character, _now), do: nil

  defp passive?(%{internal: %Internal{casting: casting, in_combat: in_combat}, unit: %Unit{target: target}}) do
    not is_struct(casting, Cast) and not (in_combat == true and is_integer(target) and target > 0)
  end

  defp passive?(_character), do: false
end
