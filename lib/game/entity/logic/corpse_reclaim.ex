defmodule ThistleTea.Game.Entity.Logic.CorpseReclaim do
  @moduledoc "Pure corpse-recovery delays with five-minute decay and a two-minute cap."

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.CorpseReclaim, as: Reclaim

  @decay_ms 300_000
  @delays {30_000, 60_000, 120_000}

  def on_damage(%Character{unit: %{health: 0}} = character, previous_health, now) when previous_health > 0 do
    previous = character.internal.corpse_reclaim.expires_at
    periods = if is_integer(previous) and previous > now, do: min(div(previous - now, @decay_ms) + 2, 3), else: 1
    reclaim = %Reclaim{expires_at: now + periods * @decay_ms}
    %{character | internal: %{character.internal | corpse_reclaim: reclaim}}
  end

  def on_damage(entity, _previous_health, _now), do: entity

  def release(%Character{} = character, now) do
    reclaim = %{character.internal.corpse_reclaim | released_at: now}
    %{character | internal: %{character.internal | corpse_reclaim: reclaim}}
  end

  def clear_release(%Character{} = character) do
    reclaim = %{character.internal.corpse_reclaim | released_at: nil}
    %{character | internal: %{character.internal | corpse_reclaim: reclaim}}
  end

  def clear_release(entity), do: entity

  def delay_ms(%Reclaim{expires_at: expires_at}, now) when is_integer(expires_at) do
    count = div(max(expires_at - now, 0), @decay_ms) |> min(2)
    elem(@delays, count)
  end

  def delay_ms(%Reclaim{}, _now), do: elem(@delays, 0)

  def remaining_ms(%Reclaim{released_at: released_at} = reclaim, now) when is_integer(released_at) do
    max(released_at + delay_ms(reclaim, released_at) - now, 0)
  end

  def remaining_ms(%Reclaim{}, _now), do: 0

  def ready?(%Reclaim{released_at: released_at} = reclaim, now) when is_integer(released_at) do
    now >= released_at + delay_ms(reclaim, now)
  end

  def ready?(%Reclaim{}, _now), do: false
end
