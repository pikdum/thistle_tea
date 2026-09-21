defmodule ThistleTea.Game.Entity.Logic.Rest do
  @moduledoc """
  Rested XP following vmangos: while resting (tavern trigger or capital
  city) the bonus pool accrues at next_level_xp / 1_152_000 per second up
  to 0.75 x next_level_xp (the client displays the pool doubled), and kill
  XP spends it one-for-one up to the base XP for a doubled total.
  Offline time earns the same rate in rest areas and one quarter in the
  wilderness. Logout settles online time and login consumes the saved offline
  interval once. The pool lives on `internal.rest_bonus`;
  `player.rest_state_experience` and the rest-state byte are its client mirrors,
  written only here.
  """
  import Bitwise, only: [&&&: 2, |||: 2, bnot: 1]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.Core

  @player_flag_resting 0x20

  @rest_state_rested 1
  @rest_state_normal 2

  @rested_threshold 10
  @normal_threshold 1

  @accrual_divisor 1_152_000
  @pool_cap_factor 0.75
  @update_interval 10_000

  def player_flag_resting, do: @player_flag_resting

  def resting?(%{internal: internal}), do: internal.rest_type != nil

  def rest_type(%{internal: internal}), do: internal.rest_type

  def logout(%Character{internal: %Internal{rest_logout_at: nil}} = character, now) do
    character = flush(character, now)
    %{character | internal: %{character.internal | rest_logout_at: now, rest_started_at: nil}}
  end

  def logout(%Character{} = character, _now), do: character

  def restore(%Character{internal: %Internal{rest_logout_at: logged_out}} = character, now)
      when is_integer(logged_out) do
    multiplier = if resting?(character), do: 1.0, else: 0.25
    gained = accrued(character, logged_out, now) * multiplier
    character = set_bonus(character, character.internal.rest_bonus + gained)
    started_at = if resting?(character), do: now
    %{character | internal: %{character.internal | rest_logout_at: nil, rest_started_at: started_at}}
  end

  def restore(%Character{} = character, _now), do: character

  def next_tick_at(%Character{internal: %Internal{rest_logout_at: nil, rest_started_at: started}} = character)
      when is_integer(started) do
    if resting?(character) and character.internal.rest_bonus < next_level_xp(character) * @pool_cap_factor,
      do: started + @update_interval
  end

  def next_tick_at(_character), do: nil

  def tick(%Character{} = character, now) do
    case next_tick_at(character) do
      at when is_integer(at) and at <= now ->
        updated = flush(character, now)
        if updated.player == character.player, do: updated, else: Core.mark_broadcast_update(updated)

      _ ->
        character
    end
  end

  def tick(entity, _now), do: entity

  def start(character, rest_type, now) do
    character = flush(character, now)
    internal = %{character.internal | rest_type: rest_type, rest_started_at: now}
    player = %{character.player | flags: (character.player.flags || 0) ||| @player_flag_resting}
    %{character | internal: internal, player: player}
  end

  def stop(character, now) do
    character = flush(character, now)
    internal = %{character.internal | rest_type: nil, rest_started_at: nil}
    player = %{character.player | flags: (character.player.flags || 0) &&& bnot(@player_flag_resting)}
    %{character | internal: internal, player: player}
  end

  def flush(%{internal: internal} = character, now) do
    case internal do
      %{rest_type: rest_type, rest_started_at: started_at, rest_logout_at: nil}
      when rest_type != nil and is_integer(started_at) ->
        gained = accrued(character, started_at, now)

        character
        |> set_bonus((internal.rest_bonus || 0.0) + gained)
        |> put_in_internal(:rest_started_at, max(started_at, now))

      _not_resting ->
        character
    end
  end

  defp accrued(character, started_at, now) do
    max(now - started_at, 0) / 1000.0 * next_level_xp(character) / @accrual_divisor
  end

  def spend(character, xp, now) when is_integer(xp) and xp > 0 do
    character = flush(character, now)
    bonus = character.internal.rest_bonus || 0.0
    spent = min(trunc(bonus), xp)

    {set_bonus(character, bonus - spent), spent}
  end

  def spend(character, _xp, _now), do: {character, 0}

  def set_bonus(%{player: player} = character, bonus) do
    bonus = bonus |> max(0.0) |> min(next_level_xp(character) * @pool_cap_factor)

    rest_state =
      cond do
        bonus > @rested_threshold -> @rest_state_rested
        bonus <= @normal_threshold -> @rest_state_normal
        true -> player.rest_state
      end

    player = %{player | rest_state_experience: trunc(bonus), rest_state: rest_state}
    put_in_internal(%{character | player: player}, :rest_bonus, bonus)
  end

  defp next_level_xp(%{player: %{next_level_xp: next_level_xp}}) when is_integer(next_level_xp) and next_level_xp > 0 do
    next_level_xp
  end

  defp next_level_xp(_character), do: 0

  defp put_in_internal(%{internal: internal} = character, key, value) do
    %{character | internal: Map.replace!(internal, key, value)}
  end
end
