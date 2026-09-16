defmodule ThistleTea.Game.Entity.Logic.Breathing do
  @moduledoc """
  Player breath reserves, surface recovery, and drowning pulses. Liquid height
  and damage rolls are supplied by the owner; timer transitions emit client
  effects and damage uses the shared health/death lifecycle.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects

  defstruct [:remaining, :duration, :updated_at, :next_damage_at, scale: -1]

  @breath_ms 60_000
  @pulse_ms 2_000

  def needs_tick?(%Character{internal: %Internal{breath: %__MODULE__{}}}), do: true
  def needs_tick?(%Character{movement_block: %MovementBlock{} = movement}), do: MovementBlock.swimming?(movement)
  def needs_tick?(_entity), do: false

  def update(%Character{} = character, liquid_surface, now, damage_bonus \\ 0, body_height \\ 2.0) do
    depth = depth(character, liquid_surface)
    submerged? = depth > body_height * scale(character)

    if not Death.alive?(character) or depth <= 0 or character.internal.godmode do
      stop(character)
    else
      update_timer(character, submerged?, now, damage_bonus)
    end
  end

  defp depth(%Character{movement_block: %MovementBlock{position: {_, _, z, _}}}, surface) when is_number(surface),
    do: surface - z

  defp depth(_character, _surface), do: 0

  defp scale(%Character{object: %{scale_x: scale}}) when is_number(scale) and scale > 0, do: scale
  defp scale(_character), do: 1.0

  defp update_timer(character, submerged?, now, damage_bonus) do
    duration = duration(character)
    draining? = submerged? and duration > 0

    case character.internal.breath do
      nil when draining? ->
        timer = %__MODULE__{remaining: duration, duration: duration, updated_at: now}
        character |> put_timer(timer) |> project(timer)

      %__MODULE__{} = previous ->
        advance(character, previous, duration, draining?, now, damage_bonus)

      _ ->
        character
    end
  end

  defp advance(character, previous, duration, draining?, now, damage_bonus) do
    maximum = if duration > 0, do: duration, else: previous.duration
    remaining = previous.remaining + max(now - previous.updated_at, 0) * previous.scale + maximum - previous.duration

    timer = %{
      previous
      | remaining: remaining |> max(0) |> min(maximum),
        duration: maximum,
        scale: if(draining?, do: -1, else: 10),
        updated_at: now
    }

    timer = if draining?, do: timer, else: %{timer | next_damage_at: nil}
    character = put_timer(character, timer)

    if not draining? and timer.remaining == maximum do
      stop(character)
    else
      character =
        if timer.scale != previous.scale or timer.duration != previous.duration,
          do: project(character, timer),
          else: character

      maybe_drown(character, timer, now, damage_bonus)
    end
  end

  defp maybe_drown(character, %__MODULE__{remaining: 0, scale: -1} = timer, now, damage_bonus) do
    if is_nil(timer.next_damage_at) or now >= timer.next_damage_at do
      damage = max(div(character.unit.max_health, 5) + damage_bonus, 1)

      character = put_timer(character, %{timer | next_damage_at: now + @pulse_ms})

      character =
        if Aura.school_immune?(character, :physical) do
          character
        else
          character
          |> Effects.enqueue(Effects.environmental_damage(:drowning, damage))
          |> Core.take_damage(damage, now, environmental?: true)
        end

      if Death.alive?(character), do: character, else: stop(character)
    else
      character
    end
  end

  defp maybe_drown(character, _timer, _now, _damage_bonus), do: character

  defp duration(character) do
    if Aura.has_aura?(character, :water_breathing) do
      0
    else
      character
      |> Aura.auras_of_type(:water_breathing_pct)
      |> Enum.reduce(@breath_ms, fn aura, duration -> duration * (100 + aura.amount) / 100 end)
      |> trunc()
      |> max(0)
    end
  end

  defp stop(%Character{internal: %Internal{breath: nil}} = character), do: character

  defp stop(character) do
    character |> put_timer(nil) |> Effects.enqueue(%Effects.StopMirrorTimer{timer: 1})
  end

  defp put_timer(character, timer), do: %{character | internal: %{character.internal | breath: timer}}

  defp project(character, timer) do
    Effects.enqueue(character, %Effects.StartMirrorTimer{
      timer: 1,
      remaining: timer.remaining,
      duration: timer.duration,
      scale: timer.scale
    })
  end
end
