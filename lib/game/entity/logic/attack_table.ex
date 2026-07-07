defmodule ThistleTea.Game.Entity.Logic.AttackTable do
  @moduledoc """
  Vanilla melee attack table ported from vmangos `Unit::RollMeleeOutcomeAgainst`:
  one roll walks miss → dodge → parry → glancing → block → crit → crushing in
  order, with weapon-skill/defense-skill adjustments (both approximated as
  level × 5), and the outcome maps to damage modifiers plus the hit-info and
  victim-state values encoded in SMSG_ATTACKERSTATEUPDATE. Armor mitigation
  (`CalcArmorReducedDamage`) is applied to physical damage before the outcome
  modifiers.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Math

  @hitinfo_affects_victim 0x2
  @hitinfo_miss 0x10
  @hitinfo_critical 0x80
  @hitinfo_glancing 0x4000
  @hitinfo_crushing 0x8000

  @victimstate_unaffected 0
  @victimstate_normal 1
  @victimstate_dodge 2
  @victimstate_parry 3
  @victimstate_blocks 5

  @unit_flag_stunned 0x00040000
  @extra_flag_no_parry 0x4
  @extra_flag_no_block 0x10
  @extra_flag_always_crush 0x2000

  @base_miss_chance 5.0
  @default_crit_chance 5.0
  @mob_avoidance_chance 5.0
  @mob_block_cap 5.0
  @crit_multiplier 2.0
  @crushing_multiplier 1.5
  @armor_reduction_cap 0.75

  def attacker_context(%{unit: %Unit{} = unit} = attacker) do
    %{
      caster_level: unit.level || 1,
      caster_player?: player?(attacker),
      crit_chance: attacker_crit_chance(attacker) + Aura.flat_amount(attacker, :mod_crit_percent),
      always_crush?: always_crush?(attacker),
      caster_position: attacker_position(attacker)
    }
  end

  def attacker_context(_attacker), do: %{}

  def resolve(defender, attack, damage, opts \\ []) when is_map(attack) do
    ctx = context(defender, attack)
    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end)

    ctx
    |> roll_outcome(roll)
    |> apply_outcome(ctx, damage, opts)
  end

  def roll_special(defender, attack, opts \\ []) when is_map(attack) do
    ctx = context(defender, attack)
    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end)

    case roll_special_outcome(ctx, roll) do
      :normal ->
        crit_roll = Keyword.get_lazy(opts, :crit_roll, fn -> Math.random_int(0, 9_999) end)
        crit? = crit_roll < crit_bp(ctx)
        %{outcome: if(crit?, do: :crit, else: :normal), crit?: crit?}

      outcome ->
        %{outcome: outcome, crit?: false}
    end
  end

  def armor_reduced_damage(damage, armor, attacker_level)
      when is_integer(damage) and is_integer(attacker_level) and attacker_level > 0 do
    armor = max(armor || 0, 0)
    reduction = 0.1 * armor / (8.5 * attacker_level + 40.0)
    reduction = min(reduction / (1.0 + reduction), @armor_reduction_cap)

    max(damage - trunc(damage * reduction), 1)
  end

  def armor_reduced_damage(damage, _armor, _attacker_level), do: damage

  defp context(defender, attack) do
    unit = defender_unit(defender)
    defender_level = unit.level || 1
    defender_player? = player?(defender)
    caster_level = positive_or(Map.get(attack, :caster_level), defender_level)
    attack_skill = positive_or(Map.get(attack, :caster_attack_skill), caster_level * 5)
    skill_diff = attack_skill - defense_skill(defender, defender_level)

    %{
      caster_level: caster_level,
      caster_player?: Map.get(attack, :caster_player?, false),
      crit_chance: Map.get(attack, :crit_chance) || @default_crit_chance,
      always_crush?: Map.get(attack, :always_crush?, false),
      spell_swing?: is_integer(Map.get(attack, :queued_spell_id)),
      physical?: physical_school?(Map.get(attack, :spell_school_mask)),
      skill_diff: skill_diff,
      defender_level: defender_level,
      defender_player?: defender_player?,
      defender_class: unit.class,
      defender_agility: unit.agility || 0,
      defender_strength: unit.strength || 0,
      defender_armor: unit.normal_resistance || 0,
      defender_block_bonus: Aura.flat_amount(defender, :mod_block_percent),
      defender_bonuses: unit.equipment_bonuses || %{},
      defender_extra_flags: extra_flags(defender),
      standing?: (unit.stand_state || 0) == 0,
      from_behind?: from_behind?(defender, Map.get(attack, :caster_position)),
      avoidance_disabled?: casting?(defender) or stunned?(unit)
    }
  end

  defp roll_outcome(ctx, roll) do
    [
      {:miss, miss_bp(ctx)},
      sitting_crit_step(ctx),
      {:dodge, dodge_bp(ctx)},
      {:parry, parry_bp(ctx)},
      {:glancing, glancing_bp(ctx)},
      {:block, block_bp(ctx)},
      {:crit, crit_bp(ctx)},
      {:crushing, crushing_bp(ctx)}
    ]
    |> Enum.reject(&is_nil/1)
    |> walk_steps(roll)
  end

  defp roll_special_outcome(ctx, roll) do
    walk_steps(
      [
        {:miss, miss_bp(ctx)},
        {:dodge, dodge_bp(ctx)},
        {:parry, parry_bp(ctx)},
        {:block, block_bp(ctx)}
      ],
      roll
    )
  end

  defp walk_steps(steps, roll) do
    steps
    |> Enum.reduce_while(0, fn {outcome, chance_bp}, acc ->
      cond do
        chance_bp >= 10_000 -> {:halt, outcome}
        chance_bp > 0 and roll < acc + chance_bp -> {:halt, outcome}
        true -> {:cont, acc + max(chance_bp, 0)}
      end
    end)
    |> case do
      outcome when is_atom(outcome) -> outcome
      _acc -> :normal
    end
  end

  defp sitting_crit_step(%{defender_player?: true, standing?: false} = ctx) do
    if ctx.crit_chance > 0 or not ctx.caster_player?, do: {:crit, 10_000}
  end

  defp sitting_crit_step(_ctx), do: nil

  defp miss_bp(%{standing?: false}), do: 0

  defp miss_bp(ctx) do
    skill_bonus =
      cond do
        ctx.defender_player? -> ctx.skill_diff * 0.04
        ctx.skill_diff < -10 -> ctx.skill_diff * 0.2
        true -> ctx.skill_diff * 0.1
      end

    (@base_miss_chance - skill_bonus)
    |> low_level_scale(ctx)
    |> clamp(0.0, 60.0)
    |> bp()
  end

  defp dodge_bp(%{avoidance_disabled?: true}), do: 0
  defp dodge_bp(%{defender_player?: true, from_behind?: true}), do: 0

  defp dodge_bp(ctx) do
    base =
      if ctx.defender_player? do
        CombatRatings.dodge_chance(ctx.defender_class, ctx.defender_level, ctx.defender_agility)
      else
        @mob_avoidance_chance
      end

    (base - avoidance_skill_bonus(ctx))
    |> low_level_scale(ctx)
    |> max(0.0)
    |> bp()
  end

  defp parry_bp(%{avoidance_disabled?: true}), do: 0
  defp parry_bp(%{from_behind?: true}), do: 0

  defp parry_bp(%{defender_player?: true} = ctx) do
    (CombatRatings.parry_chance(ctx.defender_class) - ctx.skill_diff * 0.04)
    |> max(0.0)
    |> bp()
  end

  defp parry_bp(ctx) do
    if (ctx.defender_extra_flags &&& @extra_flag_no_parry) == 0 do
      skill_bonus =
        if ctx.skill_diff < -10, do: ctx.skill_diff * 0.6, else: ctx.skill_diff * 0.2

      (@mob_avoidance_chance - skill_bonus)
      |> low_level_scale(ctx)
      |> max(0.0)
      |> bp()
    else
      0
    end
  end

  defp glancing_bp(%{caster_player?: true, defender_player?: false, spell_swing?: false} = ctx) do
    (10 + -ctx.skill_diff * 2)
    |> max(0)
    |> bp()
    |> min(4_000)
  end

  defp glancing_bp(_ctx), do: 0

  defp block_bp(%{avoidance_disabled?: true}), do: 0
  defp block_bp(%{from_behind?: true}), do: 0

  defp block_bp(%{defender_player?: true} = ctx) do
    (CombatRatings.block_chance(ctx.defender_bonuses) + ctx.defender_block_bonus - ctx.skill_diff * 0.04)
    |> max(0.0)
    |> bp()
  end

  defp block_bp(ctx) do
    if (ctx.defender_extra_flags &&& @extra_flag_no_block) == 0 do
      (@mob_avoidance_chance - ctx.skill_diff * 0.1)
      |> min(@mob_block_cap)
      |> low_level_scale(ctx)
      |> max(0.0)
      |> bp()
    else
      0
    end
  end

  defp crit_bp(ctx) do
    skill_term =
      if ctx.defender_player? or ctx.skill_diff > 0 do
        ctx.skill_diff * 0.04
      else
        ctx.skill_diff * 0.2
      end

    (ctx.crit_chance + skill_term)
    |> max(0.0)
    |> bp()
  end

  defp crushing_bp(%{caster_player?: true}), do: 0
  defp crushing_bp(%{spell_swing?: true}), do: 0
  defp crushing_bp(%{always_crush?: true}), do: 10_000

  defp crushing_bp(ctx) do
    defense_gap = -ctx.skill_diff

    if defense_gap <= -15 do
      -defense_gap * 200 - 1_500
    else
      0
    end
  end

  defp apply_outcome(:miss, _ctx, _damage, _opts) do
    %{
      outcome: :miss,
      damage: 0,
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim ||| @hitinfo_miss,
      victim_state: @victimstate_unaffected
    }
  end

  defp apply_outcome(:dodge, _ctx, _damage, _opts) do
    avoided(:dodge, @victimstate_dodge)
  end

  defp apply_outcome(:parry, _ctx, _damage, _opts) do
    avoided(:parry, @victimstate_parry)
  end

  defp apply_outcome(:glancing, ctx, damage, opts) do
    factor_roll = Keyword.get_lazy(opts, :glance_roll, fn -> :rand.uniform() end)
    damage = trunc(mitigated_damage(ctx, damage) * glancing_factor(ctx, factor_roll))

    %{
      outcome: :glancing,
      damage: max(damage, 1),
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim ||| @hitinfo_glancing,
      victim_state: @victimstate_normal
    }
  end

  defp apply_outcome(:block, ctx, damage, _opts) do
    damage = mitigated_damage(ctx, damage)
    blocked = min(block_value(ctx), damage)

    %{
      outcome: :block,
      damage: damage - blocked,
      blocked_amount: blocked,
      hit_info: @hitinfo_affects_victim,
      victim_state: if(blocked >= damage, do: @victimstate_blocks, else: @victimstate_normal)
    }
  end

  defp apply_outcome(:crit, ctx, damage, _opts) do
    %{
      outcome: :crit,
      damage: trunc(mitigated_damage(ctx, damage) * @crit_multiplier),
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim ||| @hitinfo_critical,
      victim_state: @victimstate_normal
    }
  end

  defp apply_outcome(:crushing, ctx, damage, _opts) do
    %{
      outcome: :crushing,
      damage: trunc(mitigated_damage(ctx, damage) * @crushing_multiplier),
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim ||| @hitinfo_crushing,
      victim_state: @victimstate_normal
    }
  end

  defp apply_outcome(:normal, ctx, damage, _opts) do
    %{
      outcome: :normal,
      damage: mitigated_damage(ctx, damage),
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim,
      victim_state: @victimstate_normal
    }
  end

  defp avoided(outcome, victim_state) do
    %{
      outcome: outcome,
      damage: 0,
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim,
      victim_state: victim_state
    }
  end

  defp mitigated_damage(%{physical?: false}, damage), do: damage

  defp mitigated_damage(ctx, damage) do
    armor_reduced_damage(damage, ctx.defender_armor, ctx.caster_level)
  end

  defp glancing_factor(ctx, factor_roll) do
    defense_gap = -ctx.skill_diff
    low = clamp(1.3 - 0.05 * defense_gap, 0.01, 0.91)
    high = clamp(1.2 - 0.03 * defense_gap, 0.2, 0.99)

    low + (high - low) * clamp(factor_roll, 0.0, 1.0)
  end

  defp block_value(%{defender_player?: true} = ctx) do
    CombatRatings.block_value(ctx.defender_bonuses, ctx.defender_strength)
  end

  defp block_value(ctx) do
    div(ctx.defender_level, 2) + div(ctx.defender_strength, 20)
  end

  defp avoidance_skill_bonus(%{defender_player?: true} = ctx), do: ctx.skill_diff * 0.04
  defp avoidance_skill_bonus(ctx), do: ctx.skill_diff * 0.1

  defp low_level_scale(chance, %{defender_player?: false, defender_level: level}) when level < 10 do
    chance * level / 10
  end

  defp low_level_scale(chance, _ctx), do: chance

  defp attacker_crit_chance(%{unit: %Unit{} = unit} = attacker) do
    if player?(attacker) do
      CombatRatings.melee_crit_chance(unit.class, unit.level || 1, unit.agility || 0)
    else
      @default_crit_chance
    end
  end

  defp attacker_crit_chance(_attacker), do: @default_crit_chance

  defp always_crush?(entity) do
    (extra_flags(entity) &&& @extra_flag_always_crush) != 0
  end

  defp attacker_position(%{movement_block: %{position: {x, y, z, _o}}}), do: {x, y, z}
  defp attacker_position(_attacker), do: nil

  defp from_behind?(%{movement_block: %{position: {x, y, _z, o}}}, {ax, ay, _az}) do
    Math.behind?({x, y, o}, {ax, ay})
  end

  defp from_behind?(_defender, _position), do: false

  defp casting?(%{internal: %Internal{casting: casting}}), do: not is_nil(casting)
  defp casting?(_defender), do: false

  defp stunned?(%Unit{flags: flags}) when is_integer(flags), do: (flags &&& @unit_flag_stunned) != 0
  defp stunned?(_unit), do: false

  defp extra_flags(%{internal: %Internal{creature: %Creature{extra_flags: flags}}}) when is_integer(flags), do: flags
  defp extra_flags(_entity), do: 0

  defp defender_unit(%{unit: %Unit{} = unit}), do: unit
  defp defender_unit(_defender), do: %Unit{}

  defp player?(entity), do: is_map(Map.get(entity, :player))

  defp defense_skill(entity, level) do
    case Map.get(entity, :player) do
      %{skills: skills} when is_map(skills) and map_size(skills) > 0 ->
        Skills.value(skills, Skills.defense_skill(), level * 5)

      _not_player ->
        level * 5
    end
  end

  defp physical_school?(mask) when is_integer(mask) and mask > 0, do: (mask &&& 0x1) != 0
  defp physical_school?(_mask), do: true

  defp positive_or(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or(_value, default), do: default

  defp bp(chance) when is_number(chance), do: trunc(chance * 100)

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
