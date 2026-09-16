defmodule ThistleTea.Game.Entity.Logic.Intoxication do
  @moduledoc """
  Alcohol accumulation and ten-second sobering for players. The client derives
  drunkenness messages and visual effects from the player inebriation field.
  """
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Core

  @sober_interval_ms 10_000
  @sober_amount 256
  @maximum 65_535

  def drink(%Character{unit: %{health: health}} = character, amount, now)
      when health > 0 and is_integer(amount) and amount != 0 and is_integer(now) do
    character = tick(character, now)
    value = ((character.player.drunk_value || 0) + amount * 256) |> max(0) |> min(@maximum)
    put_value(character, value, character.internal.next_sober_at || now + @sober_interval_ms)
  end

  def drink(entity, _amount, _now), do: entity

  def tick(%Character{player: %{drunk_value: value}} = character, now)
      when is_integer(value) and value > 0 and is_integer(now) do
    case character.internal.next_sober_at do
      nil -> put_value(character, value, now + @sober_interval_ms)
      at when at <= now -> put_value(character, max(value - @sober_amount, 0), now + @sober_interval_ms)
      _at -> character
    end
  end

  def tick(entity, _now), do: entity

  def clear(%Character{} = character), do: put_value(character, 0, nil)
  def clear(entity), do: entity

  def needs_tick?(%Character{player: %{drunk_value: value}}) when is_integer(value), do: value > 0
  def needs_tick?(_entity), do: false

  defp put_value(character, value, deadline) do
    %{
      character
      | player: %{character.player | drunk_value: value},
        internal: %{character.internal | next_sober_at: if(value > 0, do: deadline)}
    }
    |> Core.mark_broadcast_update()
  end
end
