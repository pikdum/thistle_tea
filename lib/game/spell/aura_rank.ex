defmodule ThistleTea.Game.Spell.AuraRank do
  @moduledoc """
  Level eligibility for ranked buffs. Recipients may be ten levels below a
  rank's spell level. Explicit casts select an eligible ancestor; group
  casts exclude ineligible recipients, while persistent party auras choose
  a rank independently for each recipient.
  """

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @friendly_targets [
    :target_ally,
    :party_member,
    :chain_heal,
    :raid_and_class,
    :party_around_caster,
    :party_around_target,
    :aoe_ally_at_source,
    :aoe_ally_at_dest
  ]
  @negative_amount_auras [
    :mod_damage_done,
    :mod_resistance,
    :mod_stat,
    :mod_skill,
    :mod_dodge_percent,
    :mod_healing_pct,
    :mod_healing_done
  ]

  def minimum_level(%Spell{rank: rank, spell_level: level} = spell)
      when is_integer(rank) and rank > 0 and is_integer(level) do
    if not Spell.attribute?(spell, :passive) and Enum.any?(spell.effects, &ranked_buff?(spell, &1)),
      do: max(level - 10, 0),
      else: 0
  end

  def minimum_level(_spell), do: 0

  def eligible?(spell, level) when is_integer(level), do: level >= minimum_level(spell)
  def eligible?(_spell, _level), do: true

  def select(%Spell{} = spell, level, ancestors) do
    if eligible?(spell, level), do: spell, else: Enum.find(ancestors, &(&1.spell_level <= level + 10))
  end

  def party_aura?(%Spell{effects: effects}), do: Enum.any?(effects, &(&1.type == :apply_area_aura))

  def requires_check?(caster, spell, opts \\ [])

  def requires_check?(%Character{}, spell, opts) do
    is_nil(Keyword.get(opts, :cast_item_guid)) and not Keyword.get(opts, :triggered?, false) and
      not Spell.attribute?(spell, :allow_low_level_buff) and minimum_level(spell) > 0
  end

  def requires_check?(_caster, _spell, _opts), do: false

  def validate(caster, spell, %{level: level}, opts) do
    if not requires_check?(caster, spell, opts) or eligible?(spell, level),
      do: :ok,
      else: {:error, :lowlevel}
  end

  def validate(_caster, _spell, _target, _opts), do: :ok

  defp ranked_buff?(spell, %Effect{type: type, implicit_target_a: target} = effect) do
    (type == :apply_area_aura or (type == :apply_aura and target in @friendly_targets)) and positive?(spell, effect)
  end

  defp positive?(spell, %Effect{aura: aura, base_points: amount} = effect) do
    cond do
      Spell.custom?(spell, :positive) -> true
      Spell.custom?(spell, :negative) or Spell.attribute?(spell, :negative) -> false
      aura in @negative_amount_auras and is_number(amount) and amount < 0 -> false
      true -> not Spell.harmful?(%{spell | effects: [effect]})
    end
  end
end
