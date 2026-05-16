defmodule ThistleTea.Game.Spell.Cast do
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets

  defstruct [
    :spell,
    :targets,
    :cast_time_ms,
    :channel_ms,
    :channel_tick_ms,
    :next_channel_tick_at,
    channel_go_sent?: false,
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

  def advance_channel_tick(%__MODULE__{channel_tick_ms: tick_ms, next_channel_tick_at: next_tick_at} = cast, now)
      when is_integer(tick_ms) and tick_ms > 0 and is_integer(next_tick_at) do
    %{cast | next_channel_tick_at: advance_tick(next_tick_at, tick_ms, now), channel_go_sent?: true}
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
end
