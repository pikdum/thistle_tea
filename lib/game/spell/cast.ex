defmodule ThistleTea.Game.Spell.Cast do
  @moduledoc """
  An in-progress cast: spell, targets, completion time, and channel tick
  state for channeled spells.
  """
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets

  defstruct [
    :spell,
    :targets,
    :cast_time_ms,
    :channel_ms,
    :channel_tick_ms,
    :next_channel_tick_at,
    :cast_item_guid,
    modifier_holder_ids: [],
    channel_started?: false,
    consume_item: false,
    pushback_count: 0,
    started_at: 0,
    ends_at: 0
  ]

  def new(%Spell{} = spell, %Targets{} = targets, now) when is_integer(now) do
    cast_time_ms = normalize_time(spell.cast_time_ms)
    channel_ms = if Spell.attribute?(spell, :channeled), do: normalize_time(spell.duration_ms), else: 0
    channel_tick_ms = if channel_ms > 0, do: Spell.channel_tick_ms(spell)

    %__MODULE__{
      spell: spell,
      targets: targets,
      cast_time_ms: cast_time_ms,
      channel_ms: channel_ms,
      channel_tick_ms: channel_tick_ms,
      next_channel_tick_at: next_channel_tick_at(now, cast_time_ms, channel_tick_ms),
      started_at: now,
      ends_at: now + cast_time_ms + channel_ms
    }
  end

  def spell_id(%__MODULE__{spell: %Spell{id: id}}), do: id
  def spell_id(_cast), do: 0

  def channeled?(%__MODULE__{channel_ms: channel_ms}) when is_integer(channel_ms) and channel_ms > 0, do: true
  def channeled?(_cast), do: false

  def apply_speed_modifier(%__MODULE__{} = cast, modifier) when is_number(modifier) and modifier != 0 do
    cast_time_ms = trunc(cast.cast_time_ms * 100 / max(100 + modifier, 1))
    delta = cast_time_ms - cast.cast_time_ms

    %{
      cast
      | cast_time_ms: cast_time_ms,
        ends_at: cast.ends_at + delta,
        next_channel_tick_at: shift_time(cast.next_channel_tick_at, delta)
    }
  end

  def apply_speed_modifier(%__MODULE__{} = cast, _modifier), do: cast

  def push_back_cast(%__MODULE__{cast_time_ms: cast_time_ms} = cast, now)
      when is_integer(cast_time_ms) and cast_time_ms > 0 and is_integer(now) do
    {cast, requested} = take_pushback_delay(cast)
    new_ends_at = min(cast.ends_at + requested, now + cast_time_ms + (cast.channel_ms || 0))
    delta = max(new_ends_at - cast.ends_at, 0)

    cast = %{
      cast
      | ends_at: cast.ends_at + delta,
        cast_time_ms: cast_time_ms + channel_pushback_delta(cast, delta),
        next_channel_tick_at: shift_time(cast.next_channel_tick_at, delta)
    }

    {cast, delta}
  end

  def push_back_cast(%__MODULE__{} = cast, _now), do: {cast, 0}

  def shorten_channel(%__MODULE__{ends_at: ends_at} = cast, now) when is_integer(ends_at) and is_integer(now) do
    {cast, requested} = take_pushback_delay(cast)
    remaining = max(ends_at - now, 0)
    reduction = min(requested, remaining)
    new_remaining = remaining - reduction
    {%{cast | ends_at: now + new_remaining}, reduction, new_remaining}
  end

  def shorten_channel(%__MODULE__{} = cast, _now), do: {cast, 0, 0}

  defp take_pushback_delay(%__MODULE__{pushback_count: count} = cast) when is_integer(count) do
    delay = if count < 5, do: 1_000 - count * 200, else: 200
    {%{cast | pushback_count: count + 1}, delay}
  end

  defp take_pushback_delay(%__MODULE__{} = cast), do: {%{cast | pushback_count: 1}, 1_000}

  defp channel_pushback_delta(%__MODULE__{channel_ms: channel_ms}, delta)
       when is_integer(channel_ms) and channel_ms > 0 do
    delta
  end

  defp channel_pushback_delta(_cast, _delta), do: 0

  def advance_channel_tick(%__MODULE__{channel_tick_ms: tick_ms, next_channel_tick_at: next_tick_at} = cast, now)
      when is_integer(tick_ms) and tick_ms > 0 and is_integer(next_tick_at) do
    %{cast | next_channel_tick_at: advance_tick(next_tick_at, tick_ms, now)}
  end

  def advance_channel_tick(cast, _now), do: cast

  def next_channel_delay(%__MODULE__{ends_at: ends_at, next_channel_tick_at: next_tick_at}, now)
      when is_integer(ends_at) and is_integer(next_tick_at) do
    min(max(next_tick_at - now, 0), max(ends_at - now, 0))
  end

  def next_channel_delay(%__MODULE__{ends_at: ends_at}, now) when is_integer(ends_at), do: max(ends_at - now, 0)
  def next_channel_delay(_cast, _now), do: 0

  defp advance_tick(last_tick, tick_ms, now) do
    next = last_tick + tick_ms
    if next > now, do: next, else: advance_tick(next, tick_ms, now)
  end

  defp normalize_time(value) when is_integer(value) and value > 0, do: value
  defp normalize_time(_value), do: 0

  defp next_channel_tick_at(_now, _cast_time_ms, nil), do: nil
  defp next_channel_tick_at(now, cast_time_ms, tick_ms), do: now + cast_time_ms + tick_ms

  defp shift_time(value, delta) when is_integer(value), do: value + delta
  defp shift_time(value, _delta), do: value
end
