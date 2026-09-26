defmodule ThistleTea.Game.Entity.Logic.Experience do
  @moduledoc """
  Pure player and pet experience formulas, creature modifiers, and group distribution.
  Kill rewards preserve the reference core's single-precision arithmetic and
  round ties to even after all modifiers have been applied.
  """

  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.DamageOrigin

  @group_reward_distance 74.0

  def group_reward_distance, do: @group_reward_distance

  def elite_rank?(rank), do: rank in [1, 2, 3]

  def kill_options(%Mob{internal: %{creature: %Creature{} = creature}} = mob) do
    [
      experience_multiplier: creature.experience_multiplier,
      damage_multiplier: DamageOrigin.xp_multiplier(mob),
      no_xp?: CreatureFlags.has?(mob, :no_xp) or summoned_without_xp?(mob),
      elite?: elite_rank?(creature.rank)
    ]
  end

  defp summoned_without_xp?(%Mob{unit: %{created_by_spell: spell}, internal: %{creature: creature}})
       when is_integer(spell) and spell > 0 do
    creature.creature_type in [8, 10, 11] or
      (is_number(creature.health_multiplier) and creature.health_multiplier <= 0.1)
  end

  defp summoned_without_xp?(_mob), do: false

  def gain_xp(entity, amount, opts)

  def gain_xp(%{unit: %{level: level}} = entity, amount, opts) when is_integer(amount) and amount > 0 do
    opts = %{
      max_level: Keyword.fetch!(opts, :max_level),
      next_level_xp: Keyword.fetch!(opts, :next_level_xp),
      level_up: Keyword.fetch!(opts, :level_up)
    }

    if level >= opts.max_level do
      {entity, []}
    else
      do_gain_xp(entity, current_xp(entity) + amount, [], opts)
    end
  end

  def gain_xp(entity, _amount, _opts), do: {entity, []}

  defp do_gain_xp(%{unit: %{level: level}, player: player} = entity, xp, events, opts) do
    next_level_xp = player.next_level_xp || opts.next_level_xp.(level)

    cond do
      next_level_xp <= 0 ->
        {put_xp(entity, 0), Enum.reverse(events)}

      xp >= next_level_xp and level < opts.max_level ->
        {entity, event} = opts.level_up.(entity, level + 1)
        entity = put_xp_after_level(entity, xp - next_level_xp, opts.max_level)
        do_gain_xp(entity, entity.player.xp, [event | events], opts)

      true ->
        {put_xp(entity, xp), Enum.reverse(events)}
    end
  end

  defp put_xp_after_level(%{unit: %{level: level}} = entity, xp, max_level) do
    xp = if level >= max_level, do: 0, else: xp
    put_xp(entity, xp)
  end

  defp put_xp(%{player: player} = entity, xp) do
    %{entity | player: %{player | xp: xp}}
  end

  defp current_xp(%{player: %{xp: xp}}) when is_integer(xp), do: xp
  defp current_xp(_entity), do: 0

  def group_rate(3), do: 1.166
  def group_rate(4), do: 1.3
  def group_rate(5), do: 1.4
  def group_rate(count) when is_integer(count) and count > 5, do: max(1.0 - count * 0.05, 0.01)
  def group_rate(_count), do: 1.0

  def group_shares(members, mob_level, opts \\ []) do
    Enum.map(group_rewards(members, mob_level, opts), &{&1.guid, &1.xp})
  end

  def group_rewards(members, mob_level, opts \\ [])

  def group_rewards([], _mob_level, _opts), do: []

  def group_rewards(members, mob_level, opts) do
    levels = Enum.map(members, & &1.level)
    sum_level = Enum.sum(levels)
    max_level = Enum.max(levels)

    not_gray_max_level =
      levels
      |> Enum.filter(fn level -> mob_level > gray_level(level) end)
      |> Enum.max(fn -> nil end)

    base = if not_gray_max_level, do: kill_xp(not_gray_max_level, mob_level, opts), else: 0
    rate = group_rate(length(members))

    Enum.map(members, fn %{guid: guid, level: level} ->
      share = member_share(base, rate, level, sum_level, max_level, not_gray_max_level)

      %{
        guid: guid,
        xp: if(is_integer(not_gray_max_level) and level <= not_gray_max_level, do: share, else: 0),
        pet_xp: share,
        pet_max_level: not_gray_max_level
      }
    end)
  end

  defp member_share(base, rate, level, sum_level, max_level, not_gray_max_level)
       when is_integer(not_gray_max_level) and base > 0 do
    share = base * rate * level / sum_level

    if max_level == not_gray_max_level do
      trunc(share)
    else
      trunc(share / 2) + 1
    end
  end

  defp member_share(_base, _rate, _level, _sum_level, _max_level, _not_gray_max_level), do: 0

  def kill_xp(unit_level, mob_level, opts \\ [])

  def kill_xp(unit_level, mob_level, opts) when is_integer(unit_level) and is_integer(mob_level) do
    if Keyword.get(opts, :no_xp?, false) do
      0
    else
      owner_level = Keyword.get(opts, :owner_level, unit_level)
      xp = float32(base_gain(owner_level, unit_level, mob_level) * elite_multiplier(opts))
      xp = float32(xp * experience_multiplier(Keyword.get(opts, :experience_multiplier, 1.0)))
      round_xp(float32(xp * float32(Keyword.get(opts, :damage_multiplier, 1.0))))
    end
  end

  def kill_xp(_unit_level, _mob_level, _opts), do: 0

  defp elite_multiplier(opts) do
    cond do
      not Keyword.get(opts, :elite?, false) -> 1.0
      Keyword.get(opts, :non_raid_dungeon?, false) -> 2.5
      true -> 2.0
    end
  end

  defp round_xp(xp) do
    whole = trunc(xp)
    if xp - whole == 0.5, do: whole + rem(whole, 2), else: round(xp)
  end

  defp float32(value) do
    <<rounded::float-32>> = <<value::float-32>>
    rounded
  end

  defp base_gain(owner_level, unit_level, mob_level) do
    float32((owner_level * 5 + 45) * level_factor(unit_level, mob_level))
  end

  defp level_factor(unit_level, mob_level) when mob_level >= unit_level do
    float32(1.0 + float32(float32(0.05) * min(mob_level - unit_level, 4)))
  end

  defp level_factor(unit_level, mob_level) do
    if mob_level > gray_level(unit_level) do
      zero_difference = zero_difference(unit_level)
      float32((zero_difference + mob_level - unit_level) / zero_difference)
    else
      0.0
    end
  end

  def quest_xp(quest_level, reward_xp, player_level) when is_integer(reward_xp) and reward_xp > 0 do
    multiplier =
      case player_level - max(quest_level, 0) do
        diff when diff <= 5 -> 1.0
        6 -> 0.8
        7 -> 0.6
        8 -> 0.4
        9 -> 0.2
        _diff -> 0.1
      end

    trunc(Float.ceil(reward_xp * multiplier))
  end

  def quest_xp(_quest_level, _reward_xp, _player_level), do: 0

  def gray_level(player_level) when player_level <= 5, do: 0
  def gray_level(player_level) when player_level <= 39, do: player_level - 5 - div(player_level, 10)
  def gray_level(60), do: 51
  def gray_level(player_level), do: player_level - 1 - div(player_level, 5)

  def zero_difference(player_level) when player_level < 8, do: 5
  def zero_difference(player_level) when player_level < 10, do: 6
  def zero_difference(player_level) when player_level < 12, do: 7
  def zero_difference(player_level) when player_level < 16, do: 8
  def zero_difference(player_level) when player_level < 20, do: 9
  def zero_difference(player_level) when player_level < 30, do: 11
  def zero_difference(player_level) when player_level < 40, do: 12
  def zero_difference(player_level) when player_level < 45, do: 13
  def zero_difference(player_level) when player_level < 50, do: 14
  def zero_difference(player_level) when player_level < 55, do: 15
  def zero_difference(player_level) when player_level < 60, do: 16
  def zero_difference(_player_level), do: 17

  defp experience_multiplier(multiplier) when is_number(multiplier) and multiplier >= 0, do: float32(multiplier)
  defp experience_multiplier(_multiplier), do: 1.0
end
