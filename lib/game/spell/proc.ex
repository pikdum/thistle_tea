defmodule ThistleTea.Game.Spell.Proc do
  @moduledoc """
  Evaluates spell-proc eligibility from DBC proc flags and VMangos
  `spell_proc_event` restrictions.
  """
  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  @normal_hit 0x1
  @critical_hit 0x2

  def eligible?(%Spell{} = proc_spell, %Spell{} = triggering_spell, proc_type, outcome) do
    proc_flag?(proc_spell, proc_type) and
      school_allowed?(proc_spell.proc_rule, triggering_spell) and
      family_allowed?(proc_spell.proc_rule, triggering_spell) and
      outcome_allowed?(proc_spell.proc_rule, outcome)
  end

  def eligible?(_proc_spell, _triggering_spell, _proc_type, _outcome), do: false

  def roll?(%Spell{} = spell) do
    chance = proc_chance(spell)
    chance >= 100 or (chance > 0 and :rand.uniform() * 100 <= chance)
  end

  defp proc_flag?(%Spell{proc_rule: %ProcRule{proc_flags: flags}}, proc_type) when flags > 0,
    do: proc_flag?(flags, proc_type)

  defp proc_flag?(%Spell{proc_type_mask: flags}, proc_type), do: proc_flag?(flags, proc_type)

  defp proc_flag?(flags, proc_type) when is_integer(flags) do
    case proc_mask(proc_type) do
      0 -> false
      mask -> (flags &&& mask) != 0
    end
  end

  defp proc_flag?(_flags, _proc_type), do: false

  defp proc_mask(:deal_harmful_spell), do: 0x00010000
  defp proc_mask(:deal_harmful_periodic), do: 0x00040000
  defp proc_mask(_proc_type), do: 0

  defp school_allowed?(%ProcRule{school_mask: 0}, _spell), do: true

  defp school_allowed?(%ProcRule{school_mask: mask}, %Spell{} = spell) when is_integer(mask),
    do: (mask &&& Spell.school_mask(spell)) != 0

  defp school_allowed?(_rule, _spell), do: true

  defp family_allowed?(%ProcRule{} = rule, %Spell{} = spell) do
    family_matches?(rule, spell) and family_masks_match?(rule, spell)
  end

  defp family_allowed?(_rule, _spell), do: true

  defp family_matches?(%ProcRule{spell_family: 0}, _spell), do: true
  defp family_matches?(%ProcRule{spell_family: family}, %Spell{spell_family: family}), do: true
  defp family_matches?(_rule, _spell), do: false

  defp family_masks_match?(%ProcRule{family_mask_0: 0, family_mask_1: 0}, _spell), do: true

  defp family_masks_match?(%ProcRule{} = rule, %Spell{} = spell) do
    (rule.family_mask_0 &&& spell.family_flags_0) != 0 or
      (rule.family_mask_1 &&& spell.family_flags_1) != 0
  end

  defp outcome_allowed?(%ProcRule{proc_ex: proc_ex}, outcome) when is_integer(proc_ex) and proc_ex > 0 do
    (proc_ex &&& outcome_mask(outcome)) != 0
  end

  defp outcome_allowed?(_rule, outcome), do: outcome in [:normal, :crit]

  defp outcome_mask(:normal), do: @normal_hit
  defp outcome_mask(:crit), do: @critical_hit
  defp outcome_mask(_outcome), do: 0

  defp proc_chance(%Spell{proc_rule: %ProcRule{custom_chance: chance}}) when chance > 0, do: chance
  defp proc_chance(%Spell{proc_chance: chance}) when is_number(chance), do: chance
  defp proc_chance(_spell), do: 0
end
