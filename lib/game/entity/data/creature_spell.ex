defmodule ThistleTea.Game.Entity.Data.CreatureSpell do
  @moduledoc """
  One entry of a creature's spell list (vmangos `creature_spells` semantics):
  which spell to cast, at whom, how often, and the cast flags that shape
  caster behavior. Delays are converted from DB seconds to milliseconds.
  """
  import Bitwise, only: [&&&: 2]

  defstruct spell_id: 0,
            probability: 100,
            cast_target: :victim,
            target_param1: 0,
            target_param2: 0,
            cast_flags: MapSet.new(),
            delay_initial_min_ms: 0,
            delay_initial_max_ms: 0,
            delay_repeat_min_ms: 0,
            delay_repeat_max_ms: 0

  @cast_flag_bits [
    {0x001, :interrupt_previous},
    {0x002, :triggered},
    {0x004, :force_cast},
    {0x008, :main_ranged},
    {0x010, :target_unreachable},
    {0x020, :aura_not_present},
    {0x040, :only_in_melee},
    {0x080, :not_in_melee},
    {0x100, :target_casting}
  ]

  def build(%{spell_id: spell_id} = slot) when is_integer(spell_id) and spell_id > 0 do
    %__MODULE__{
      spell_id: spell_id,
      probability: normalize_probability(slot.probability),
      cast_target: cast_target(slot.cast_target),
      target_param1: slot.target_param1 || 0,
      target_param2: slot.target_param2 || 0,
      cast_flags: cast_flags(slot.cast_flags),
      delay_initial_min_ms: seconds_to_ms(slot.delay_initial_min),
      delay_initial_max_ms: seconds_to_ms(slot.delay_initial_max),
      delay_repeat_min_ms: seconds_to_ms(slot.delay_repeat_min),
      delay_repeat_max_ms: seconds_to_ms(slot.delay_repeat_max)
    }
  end

  def build(_slot), do: nil

  def flag?(%__MODULE__{cast_flags: cast_flags}, flag) when is_atom(flag) do
    MapSet.member?(cast_flags, flag)
  end

  def flag?(_entry, _flag), do: false

  def roll_initial_delay_ms(%__MODULE__{delay_initial_min_ms: min_ms, delay_initial_max_ms: max_ms}) do
    roll_between(min_ms, max_ms)
  end

  def roll_repeat_delay_ms(%__MODULE__{delay_repeat_min_ms: min_ms, delay_repeat_max_ms: max_ms}) do
    roll_between(min_ms, max_ms)
  end

  defp roll_between(min_ms, max_ms) when is_integer(min_ms) and is_integer(max_ms) and max_ms > min_ms do
    min_ms + :rand.uniform(max_ms - min_ms + 1) - 1
  end

  defp roll_between(min_ms, _max_ms) when is_integer(min_ms), do: min_ms
  defp roll_between(_min_ms, _max_ms), do: 0

  defp normalize_probability(probability) when is_integer(probability) and probability in 1..100 do
    probability
  end

  defp normalize_probability(_probability), do: 100

  defp seconds_to_ms(seconds) when is_integer(seconds) and seconds > 0, do: seconds * 1_000
  defp seconds_to_ms(_seconds), do: 0

  defp cast_flags(flags) when is_integer(flags) do
    Enum.reduce(@cast_flag_bits, MapSet.new(), fn {bit, atom}, acc ->
      if (flags &&& bit) == 0, do: acc, else: MapSet.put(acc, atom)
    end)
  end

  defp cast_flags(_flags), do: MapSet.new()

  # values follow mangos-zero's CreatureSpellTarget enum (CreatureAI.cpp),
  # not current vmangos ScriptCommands.h — upstream froze an older revision
  defp cast_target(0), do: :self
  defp cast_target(1), do: :victim
  defp cast_target(2), do: :hostile_second_aggro
  defp cast_target(3), do: :hostile_last_aggro
  defp cast_target(4), do: :hostile_random
  defp cast_target(5), do: :hostile_random_not_top
  defp cast_target(14), do: :friendly
  defp cast_target(15), do: :friendly_injured
  defp cast_target(16), do: :friendly_injured_except
  defp cast_target(17), do: :friendly_missing_buff
  defp cast_target(18), do: :friendly_missing_buff_except
  defp cast_target(other) when is_integer(other), do: other
  defp cast_target(_other), do: :victim
end
