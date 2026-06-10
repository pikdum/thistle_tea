defmodule ThistleTea.Game.Entity.Logic.Experience do
  @moduledoc false

  import Bitwise, only: [&&&: 2]

  @no_xp_at_kill 0x00000040

  def kill_xp(player_level, mob_level, opts \\ [])

  def kill_xp(player_level, mob_level, opts) when is_integer(player_level) and is_integer(mob_level) do
    if Keyword.get(opts, :no_xp?, false) or no_xp_extra_flags?(Keyword.get(opts, :extra_flags, 0)) do
      0
    else
      xp = base_gain(player_level, mob_level)
      xp = if Keyword.get(opts, :elite?, false), do: xp * 2, else: xp
      trunc(xp * experience_multiplier(Keyword.get(opts, :experience_multiplier, 1.0)))
    end
  end

  def kill_xp(_player_level, _mob_level, _opts), do: 0

  def base_gain(player_level, mob_level) when mob_level >= player_level do
    level_diff = min(mob_level - player_level, 4)
    base = player_level * 5 + 45
    div(div(base * (20 + level_diff), 10) + 1, 2)
  end

  def base_gain(player_level, mob_level) do
    gray_level = gray_level(player_level)

    if mob_level > gray_level do
      zero_difference = zero_difference(player_level)
      div((player_level * 5 + 45) * (zero_difference + mob_level - player_level), zero_difference)
    else
      0
    end
  end

  def quest_xp(quest_level, rew_money_max_level, player_level)
      when is_integer(rew_money_max_level) and rew_money_max_level > 0 do
    full_xp = rew_money_max_level / quest_xp_divisor(quest_level)

    multiplier =
      case player_level - max(quest_level, 0) do
        diff when diff <= 5 -> 1.0
        6 -> 0.8
        7 -> 0.6
        8 -> 0.4
        9 -> 0.2
        _diff -> 0.1
      end

    trunc(Float.ceil(full_xp * multiplier))
  end

  def quest_xp(_quest_level, _rew_money_max_level, _player_level), do: 0

  defp quest_xp_divisor(quest_level) when quest_level >= 65, do: 6.0
  defp quest_xp_divisor(64), do: 4.8
  defp quest_xp_divisor(63), do: 3.6
  defp quest_xp_divisor(62), do: 2.4
  defp quest_xp_divisor(61), do: 1.2
  defp quest_xp_divisor(_quest_level), do: 0.6

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

  defp no_xp_extra_flags?(flags) when is_integer(flags), do: (flags &&& @no_xp_at_kill) != 0
  defp no_xp_extra_flags?(_flags), do: false

  defp experience_multiplier(multiplier) when is_number(multiplier) and multiplier > 0, do: multiplier
  defp experience_multiplier(_multiplier), do: 1.0
end
