defmodule ThistleTea.Game.Spell.Proc do
  @moduledoc """
  Evaluates spell-proc eligibility from DBC proc flags and VMangos
  `spell_proc_event` restrictions.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  @normal_hit 0x1
  @critical_hit 0x2
  @block 0x40
  @absorb 0x400
  @periodic_positive 0x40000
  @trigger_always 0x10000
  @cast_end 0x80000

  def melee_hit_mask(outcome, damage, absorbed) do
    mask = outcome_mask(outcome)
    mask = if outcome == :block and damage > 0, do: mask ||| @normal_hit, else: mask
    if absorbed > 0, do: mask ||| @absorb, else: mask
  end

  def eligible?(%Spell{} = proc_spell, %Spell{} = triggering_spell, proc_type, outcome) do
    proc_flag?(proc_spell, proc_type) and
      school_allowed?(proc_spell.proc_rule, triggering_spell) and
      family_allowed?(proc_spell.proc_rule, triggering_spell) and
      outcome_allowed?(proc_spell.proc_rule, proc_type, outcome)
  end

  def eligible?(%Spell{} = proc_spell, nil, proc_type, outcome) do
    proc_flag?(proc_spell, proc_type) and school_allowed?(proc_spell.proc_rule, nil) and
      outcome_allowed?(proc_spell.proc_rule, proc_type, outcome)
  end

  def eligible?(_proc_spell, _triggering_spell, _proc_type, _outcome), do: false

  def roll?(spell, attack_time_ms \\ nil, roll \\ &:rand.uniform/0)

  def roll?(%Spell{} = spell, attack_time_ms, roll) when is_function(roll, 0) do
    chance = proc_chance(spell, attack_time_ms)
    chance >= 100 or (chance > 0 and roll.() * 100 <= chance)
  end

  def roll?(_spell, _attack_time_ms, _roll), do: false

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

  defp proc_mask(:kill), do: 0x00000002
  defp proc_mask(:deal_helpful_spell), do: 0x00004400
  defp proc_mask(:deal_harmful_spell), do: 0x00010000
  defp proc_mask(:deal_harmful_periodic), do: 0x00040000
  defp proc_mask(:deal_helpful_periodic), do: 0x00040000
  defp proc_mask(:deal_melee_swing), do: 0x00000004
  defp proc_mask(:deal_melee_ability), do: 0x00000010
  defp proc_mask(:take_melee_swing), do: 0x00000008
  defp proc_mask(:take_melee_ability), do: 0x00000020
  defp proc_mask(:deal_ranged_attack), do: 0x00000040
  defp proc_mask(:take_ranged_attack), do: 0x00000080
  defp proc_mask(:deal_ranged_ability), do: 0x00000100
  defp proc_mask(:take_ranged_ability), do: 0x00000200
  defp proc_mask(:take_harmful_spell), do: 0x00020000
  defp proc_mask(:take_harmful_periodic), do: 0x00080000
  defp proc_mask(_proc_type), do: 0

  defp school_allowed?(%ProcRule{school_mask: 0}, _spell), do: true

  defp school_allowed?(%ProcRule{school_mask: mask}, nil) when is_integer(mask), do: (mask &&& 1) != 0

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

  defp outcome_allowed?(%ProcRule{proc_ex: proc_ex}, proc_type, outcome) when is_integer(proc_ex) and proc_ex > 0 do
    outcome_mask = outcome_mask(outcome) ||| periodic_outcome_mask(proc_type)
    (proc_ex &&& (@trigger_always ||| @cast_end)) != 0 or (proc_ex &&& outcome_mask) != 0
  end

  defp outcome_allowed?(_rule, :deal_helpful_periodic, _outcome), do: false

  defp outcome_allowed?(_rule, _proc_type, outcome),
    do: (outcome_mask(outcome) &&& (@normal_hit ||| @critical_hit)) != 0

  defp periodic_outcome_mask(:deal_helpful_periodic), do: @periodic_positive
  defp periodic_outcome_mask(_proc_type), do: 0

  def shield_outcome_allowed?(%Spell{proc_rule: %ProcRule{proc_ex: proc_ex}}, outcome)
      when is_integer(proc_ex) and proc_ex > 0 do
    (proc_ex &&& outcome_mask(outcome)) != 0
  end

  def shield_outcome_allowed?(_spell, %{outcome: :block}), do: true

  def shield_outcome_allowed?(_spell, %{damage: damage, absorbed: absorbed} = context) do
    damage > absorbed and shield_outcome_allowed?(nil, context.outcome)
  end

  def shield_outcome_allowed?(_spell, %{outcome: outcome}), do: shield_outcome_allowed?(nil, outcome)
  def shield_outcome_allowed?(_spell, outcome), do: outcome in [:normal, :crit, :glancing, :crushing, :block]

  defp outcome_mask(%{proc_ex: mask}) when is_integer(mask), do: mask
  defp outcome_mask(%{outcome: outcome}), do: outcome_mask(outcome)

  defp outcome_mask(:normal), do: @normal_hit
  defp outcome_mask(:crit), do: @critical_hit
  defp outcome_mask(:glancing), do: @normal_hit
  defp outcome_mask(:crushing), do: @normal_hit
  defp outcome_mask(:miss), do: 0x4
  defp outcome_mask(:resist), do: 0x8
  defp outcome_mask(:dodge), do: 0x10
  defp outcome_mask(:parry), do: 0x20
  defp outcome_mask(:block), do: @block
  defp outcome_mask(:evade), do: 0x80
  defp outcome_mask(:immune), do: 0x100
  defp outcome_mask(:deflect), do: 0x200
  defp outcome_mask(:absorb), do: @absorb
  defp outcome_mask(:reflect), do: 0x800
  defp outcome_mask(_outcome), do: 0

  defp proc_chance(%Spell{proc_rule: %ProcRule{ppm_rate: ppm}}, attack_time_ms)
       when ppm > 0 and is_number(attack_time_ms) and attack_time_ms > 0 do
    min(ppm * attack_time_ms / 600, 100.0)
  end

  defp proc_chance(%Spell{proc_rule: %ProcRule{ppm_rate: ppm}}, _attack_time_ms) when ppm > 0, do: 0
  defp proc_chance(%Spell{proc_rule: %ProcRule{custom_chance: chance}}, _attack_time_ms) when chance > 0, do: chance
  defp proc_chance(%Spell{proc_chance: chance}, _attack_time_ms) when is_number(chance), do: chance
  defp proc_chance(_spell, _attack_time_ms), do: 0
end
