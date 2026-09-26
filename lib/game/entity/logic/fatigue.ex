defmodule ThistleTea.Game.Entity.Logic.Fatigue do
  @moduledoc "Deep-ocean fatigue, shore recovery, exhaustion damage, and rescue of stranded ghosts."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EnvironmentalDamage
  alias ThistleTea.Game.Entity.Logic.Taxi
  alias ThistleTea.Game.Terrain.Liquid

  defstruct [:remaining, :updated_at, :next_damage_at, scale: -1]

  @duration_ms 60_000
  @pulse_ms 2_000

  def needs_tick?(%Character{internal: %Internal{fatigue: %__MODULE__{}}}), do: true
  def needs_tick?(_entity), do: false

  def update(%Character{} = character, liquid, now, damage_bonus \\ 0) do
    cond do
      is_nil(liquid) or protected?(character) or dead_body?(character) -> stop(character)
      Liquid.high_sea?(liquid) -> advance(character, true, now, damage_bonus)
      true -> advance(character, false, now, damage_bonus)
    end
  end

  defp protected?(character) do
    character.internal.godmode or Taxi.active?(character) or
      MovementBlock.on_transport?(character.movement_block) or character.unit.shapeshift_form == 32
  end

  defp dead_body?(character), do: not Death.alive?(character) and not Death.ghost?(character)

  defp advance(%Character{internal: %Internal{fatigue: nil}} = character, true, now, _bonus) do
    timer = %__MODULE__{remaining: @duration_ms, updated_at: now}
    character |> put_timer(timer) |> project(timer)
  end

  defp advance(%Character{internal: %Internal{fatigue: nil}} = character, false, _now, _bonus), do: character

  defp advance(%Character{internal: %Internal{fatigue: previous}} = character, draining?, now, bonus) do
    remaining = previous.remaining + max(now - previous.updated_at, 0) * previous.scale

    timer = %{
      previous
      | remaining: remaining |> max(0) |> min(@duration_ms),
        scale: if(draining?, do: -1, else: 10),
        updated_at: now,
        next_damage_at: if(draining?, do: previous.next_damage_at)
    }

    character = put_timer(character, timer)

    if not draining? and timer.remaining == @duration_ms do
      stop(character)
    else
      character = if timer.scale == previous.scale, do: character, else: project(character, timer)
      maybe_exhaust(character, timer, now, bonus)
    end
  end

  defp maybe_exhaust(character, %__MODULE__{remaining: 0, scale: -1, next_damage_at: at} = timer, now, bonus)
       when is_nil(at) or now >= at do
    character = put_timer(character, %{timer | next_damage_at: now + @pulse_ms})

    if Death.ghost?(character) do
      character |> stop() |> Effects.enqueue(%Effects.RepopAtGraveyard{})
    else
      damage = max(div(character.unit.max_health, 5) + bonus, 1)
      character = EnvironmentalDamage.apply(character, :exhaustion, damage, now)
      if Death.alive?(character), do: character, else: stop(character)
    end
  end

  defp maybe_exhaust(character, _timer, _now, _bonus), do: character

  defp stop(%Character{internal: %Internal{fatigue: nil}} = character), do: character
  defp stop(character), do: character |> put_timer(nil) |> Effects.enqueue(%Effects.StopMirrorTimer{timer: 0})

  defp put_timer(character, timer), do: %{character | internal: %{character.internal | fatigue: timer}}

  defp project(character, timer) do
    Effects.enqueue(character, %Effects.StartMirrorTimer{
      timer: 0,
      remaining: timer.remaining,
      duration: @duration_ms,
      scale: timer.scale
    })
  end
end
