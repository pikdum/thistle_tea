defmodule ThistleTea.Game.Entity.Logic.AttackTable do
  @moduledoc """
  Vanilla melee attack table ported from vmangos `Unit::RollMeleeOutcomeAgainst`:
  one roll walks miss → dodge → parry → glancing → block → crit → crushing in
  order, with learned defenses and weapon-skill/defense-skill adjustments,
  and the outcome maps to damage modifiers plus the hit-info and
  victim-state values encoded in SMSG_ATTACKERSTATEUPDATE. Armor mitigation
  (`CalcArmorReducedDamage`) is applied to physical damage before the outcome
  modifiers.
  """
  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AttackDamageTaken
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.CreatureType
  alias ThistleTea.Game.Entity.Logic.Daze
  alias ThistleTea.Game.Entity.Logic.Disarm
  alias ThistleTea.Game.Entity.Logic.MechanicResistance
  alias ThistleTea.Game.Entity.Logic.PetHappiness
  alias ThistleTea.Game.Entity.Logic.ResistancePenetration
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.TargetAttackPower
  alias ThistleTea.Game.Entity.Logic.TargetDamage
  alias ThistleTea.Game.Math
  alias ThistleTea.Game.Spell

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
  @mob_block_cap 5.0
  @crit_multiplier 2.0
  @crushing_multiplier 1.5
  @armor_reduction_cap 0.75

  def attacker_context(%{unit: %Unit{} = unit} = attacker) do
    multipliers = attack_damage_multipliers(attacker)

    %{
      caster_level: unit.level || 1,
      caster_owner_guid: caster_owner_guid(attacker),
      caster_player?: player?(attacker),
      caster_class: unit.class,
      dual_wield_penalty?: offhand_weapon?(attacker) and not physical_spell_active?(attacker),
      caster_can_daze?: Daze.attacker?(attacker),
      crit_chance: attacker_crit_chance(attacker) + Aura.flat_amount(attacker, :mod_crit_percent),
      hit_chance_bonus: Aura.flat_amount(attacker, :mod_hit_chance),
      always_crush?: always_crush?(attacker),
      caster_position: attacker_position(attacker),
      damage_done_versus: Aura.misc_amounts(attacker, :mod_damage_done_versus),
      target_attack_power: TargetAttackPower.snapshot(attacker),
      target_damage: TargetDamage.snapshot(attacker),
      resistance_penetration: ResistancePenetration.snapshot(attacker),
      attack_damage_multipliers: multipliers,
      attack_power_damage: attack_power_damage(unit, multipliers),
      crit_damage_versus: Aura.misc_amounts(attacker, :mod_crit_percent_versus)
    }
  end

  def attacker_context(_attacker), do: %{}

  defp offhand_weapon?(%Character{unit: %Unit{shapeshift_form: form}}) when form in [1, 2, 3, 4, 5, 8], do: false

  defp offhand_weapon?(%Character{unit: %Unit{base_offhand_max_damage: damage}}), do: is_number(damage)
  defp offhand_weapon?(%{unit: %Unit{virtual_item_info: <<_mainhand::binary-size(8), 2, _rest::binary>>}}), do: true
  defp offhand_weapon?(_attacker), do: false

  defp physical_spell_active?(%{internal: %Internal{} = internal}) do
    not is_nil(internal.next_swing_spell) or physical_cast?(internal.casting) or physical_cast?(internal.auto_shot)
  end

  defp physical_spell_active?(_attacker), do: false

  defp physical_cast?(%{spell: %Spell{} = spell}), do: (Spell.school_mask(spell) &&& 1) != 0
  defp physical_cast?(_cast), do: false

  defp caster_owner_guid(%{internal: %{pet: %{owner_guid: owner_guid}}}) when is_integer(owner_guid), do: owner_guid
  defp caster_owner_guid(%{object: %{guid: guid}}) when is_integer(guid), do: guid
  defp caster_owner_guid(_attacker), do: nil

  defp attack_damage_multipliers(attacker) do
    multiplier =
      Aura.percent_multiplier(attacker, :mod_damage_percent_done, 1) * PetHappiness.damage_multiplier(attacker)

    offhand = 0.5 * max(100 + Aura.flat_amount(attacker, :mod_offhand_damage_pct), 0) / 100

    %{
      mainhand: multiplier * Disarm.damage_multiplier(attacker),
      offhand: multiplier * offhand
    }
  end

  defp attack_power_damage(unit, multipliers) do
    %{
      mainhand: (unit.base_attack_time || 2_000) / 14_000 * multipliers.mainhand,
      offhand: (unit.offhand_attack_time || 2_000) / 14_000 * multipliers.offhand
    }
  end

  defp target_attack_power_damage(defender, attack) do
    hand = if Map.get(attack, :offhand?, false), do: :offhand, else: :mainhand
    factor = attack |> Map.get(:attack_power_damage, %{}) |> Map.get(hand, 0)
    TargetAttackPower.bonus(defender, Map.get(attack, :target_attack_power, %{}), :melee) * factor
  end

  def resolve(defender, attack, damage, opts \\ []) when is_map(attack) do
    ctx = context(defender, attack)
    bonus = target_attack_power_damage(defender, attack) + target_damage(defender, attack)
    damage = scale_versus_damage(ctx, max(trunc(damage + bonus), 0))
    damage = AttackDamageTaken.amount(defender, damage, if(ctx.ranged?, do: :ranged, else: :melee))
    roll = Keyword.get_lazy(opts, :roll, fn -> Math.random_int(0, 9_999) end)
    outcome = roll_outcome(ctx, roll)
    result = apply_outcome(outcome, ctx, damage, opts)

    Map.put(result, :pre_armor_damage, reconstruct_pre_armor_damage(ctx, damage, result.damage))
  end

  defp target_damage(defender, attack) do
    hand = if Map.get(attack, :offhand?, false), do: :offhand, else: :mainhand
    multiplier = attack |> Map.get(:attack_damage_multipliers, %{}) |> Map.get(hand, 1.0)
    TargetDamage.bonus(defender, Map.get(attack, :target_damage, [])) * multiplier
  end

  def roll_special(defender, attack, opts \\ []) when is_map(attack) do
    ctx = %{context(defender, attack) | spell_swing?: true}
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

  def armor_reduced_damage(damage, _armor, _attacker_level) when damage <= 0, do: 0

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
    caster_player? = Map.get(attack, :caster_player?, false)
    attack_skill = non_negative_or(Map.get(attack, :caster_attack_skill), caster_level * 5)
    defense_skill = Skills.defense_value(defender, caster_player?)
    skill_diff = attack_skill - defense_skill
    defenses = CombatRatings.defensive_chances(defender)

    %{
      caster_level: caster_level,
      caster_player?: caster_player?,
      caster_class: Map.get(attack, :caster_class),
      dual_wield_penalty?: Map.get(attack, :dual_wield_penalty?, false),
      crit_chance:
        (Map.get(attack, :crit_chance) || @default_crit_chance) +
          attacker_crit_bonus(defender, attack),
      always_crush?: Map.get(attack, :always_crush?, false),
      spell_swing?: is_integer(Map.get(attack, :queued_spell_id)),
      block_allowed?: Map.get(attack, :block_allowed?, true),
      ranged?: Map.get(attack, :ranged?, false),
      physical?: physical_school?(Map.get(attack, :spell_school_mask)),
      mechanic_resistance_bp:
        trunc(MechanicResistance.chance(MechanicResistance.projection(defender), Map.get(attack, :mechanic)) * 100),
      skill_diff: skill_diff,
      capped_skill_diff: min(attack_skill, caster_level * 5) - defense_skill,
      capped_avoidance_skill_diff: min(attack_skill, caster_level * 5) - defender_level * 5,
      avoidance_skill_diff: attack_skill - defender_level * 5,
      defender_level: defender_level,
      defender_player?: defender_player?,
      defender_block_value: CombatRatings.block_value(defender),
      defender_armor:
        ResistancePenetration.resistance(
          unit.normal_resistance,
          Map.get(attack, :resistance_penetration, []),
          :physical
        ),
      defender_dodge_chance: defenses.dodge,
      defender_parry_chance: defenses.parry,
      defender_block_chance: defenses.block,
      defender_extra_flags: extra_flags(defender),
      hit_chance_bonus: hit_chance_bonus(attack),
      attacker_hit_bonus: attacker_hit_debuff(defender, attack),
      versus_damage_pct: versus_pct(attack, :damage_done_versus, defender),
      versus_crit_pct: versus_pct(attack, :crit_damage_versus, defender),
      standing?: (unit.stand_state || 0) == 0,
      from_behind?: from_behind?(defender, Map.get(attack, :caster_position)),
      avoidance_disabled?: casting?(defender) or stunned?(unit),
      block_disabled?: defender_player? and (unit.sheath_state || 0) == 0
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

  defp hit_chance_bonus(%{hit_chance_bonus: bonus}) when is_number(bonus), do: bonus
  defp hit_chance_bonus(_attack), do: 0

  defp attacker_hit_debuff(defender, %{ranged?: true}) do
    Aura.flat_amount(defender, :mod_attacker_ranged_hit_chance)
  end

  defp attacker_hit_debuff(defender, _attack), do: Aura.flat_amount(defender, :mod_attacker_melee_hit_chance)

  defp attacker_crit_bonus(defender, attack) do
    type =
      if Map.get(attack, :ranged?, false), do: :mod_attacker_ranged_crit_chance, else: :mod_attacker_melee_crit_chance

    Aura.flat_amount(defender, type)
  end

  defp versus_pct(attack, key, defender) do
    Aura.versus_amount(Map.get(attack, key), CreatureType.mask(defender))
  end

  defp scale_versus_damage(%{versus_damage_pct: pct}, damage)
       when is_integer(pct) and pct != 0 and is_integer(damage) do
    trunc(damage * max(100 + pct, 0) / 100)
  end

  defp scale_versus_damage(_ctx, damage), do: damage

  defp roll_special_outcome(ctx, roll) do
    if roll >= miss_bp(ctx) and roll < miss_bp(ctx) + ctx.mechanic_resistance_bp do
      :resist
    else
      roll_special_avoidance(ctx, roll)
    end
  end

  defp roll_special_avoidance(ctx, roll) do
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

  defp crit_multiplier(%{versus_crit_pct: pct}) when is_integer(pct) and pct != 0 do
    @crit_multiplier + pct / 100
  end

  defp crit_multiplier(_ctx), do: @crit_multiplier

  defp miss_bp(%{standing?: false}), do: 0

  defp miss_bp(ctx) do
    skill_bonus =
      cond do
        ctx.defender_player? -> ctx.skill_diff * 0.04
        ctx.skill_diff < -10 -> ctx.skill_diff * 0.2
        true -> ctx.skill_diff * 0.1
      end

    penalty = if ctx.dual_wield_penalty? and not ctx.spell_swing? and not ctx.ranged?, do: 19.0, else: 0.0

    hit_bonus =
      if ctx.skill_diff < -10 and ctx.hit_chance_bonus > 0,
        do: ctx.hit_chance_bonus - 1.0,
        else: ctx.hit_chance_bonus

    (low_level_scale(@base_miss_chance + penalty - skill_bonus, ctx) - hit_bonus - ctx.attacker_hit_bonus)
    |> clamp(0.0, 60.0)
    |> bp()
  end

  defp dodge_bp(%{ranged?: true}), do: 0
  defp dodge_bp(%{avoidance_disabled?: true}), do: 0
  defp dodge_bp(%{defender_player?: true, from_behind?: true}), do: 0

  defp dodge_bp(ctx) do
    (ctx.defender_dodge_chance - avoidance_skill_bonus(ctx))
    |> low_level_scale(ctx)
    |> max(0.0)
    |> bp()
  end

  defp parry_bp(%{ranged?: true}), do: 0
  defp parry_bp(%{defender_parry_chance: chance}) when chance <= 0, do: 0
  defp parry_bp(%{avoidance_disabled?: true}), do: 0
  defp parry_bp(%{from_behind?: true}), do: 0

  defp parry_bp(%{defender_player?: true} = ctx) do
    (ctx.defender_parry_chance - ctx.avoidance_skill_diff * 0.04)
    |> max(0.0)
    |> bp()
  end

  defp parry_bp(ctx) do
    if (ctx.defender_extra_flags &&& @extra_flag_no_parry) == 0 do
      skill_bonus =
        if ctx.capped_avoidance_skill_diff < -10,
          do: ctx.capped_avoidance_skill_diff * 0.6,
          else: ctx.capped_avoidance_skill_diff * 0.2

      (ctx.defender_parry_chance - skill_bonus)
      |> low_level_scale(ctx)
      |> max(0.0)
      |> bp()
    else
      0
    end
  end

  defp glancing_bp(%{ranged?: true}), do: 0

  defp glancing_bp(%{caster_player?: true, defender_player?: false, spell_swing?: false} = ctx) do
    (10 + -ctx.capped_skill_diff * 2)
    |> max(0)
    |> bp()
    |> min(4_000)
  end

  defp glancing_bp(_ctx), do: 0

  defp block_bp(%{ranged?: true}), do: 0
  defp block_bp(%{avoidance_disabled?: true}), do: 0
  defp block_bp(%{from_behind?: true}), do: 0
  defp block_bp(%{block_allowed?: false}), do: 0
  defp block_bp(%{block_disabled?: true}), do: 0
  defp block_bp(%{defender_block_chance: chance}) when chance <= 0, do: 0

  defp block_bp(%{defender_player?: true} = ctx) do
    (ctx.defender_block_chance - ctx.avoidance_skill_diff * 0.04)
    |> max(0.0)
    |> bp()
  end

  defp block_bp(ctx) do
    if (ctx.defender_extra_flags &&& @extra_flag_no_block) == 0 do
      (ctx.defender_block_chance - ctx.skill_diff * 0.1)
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
        ctx.capped_skill_diff * 0.2
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
    damage = max(trunc(mitigated_damage(ctx, damage) * glancing_factor(ctx, factor_roll)), min(damage, 1))

    %{
      outcome: :glancing,
      damage: damage,
      blocked_amount: 0,
      hit_info: @hitinfo_affects_victim ||| @hitinfo_glancing,
      victim_state: @victimstate_normal
    }
  end

  defp apply_outcome(:block, ctx, damage, _opts) do
    damage = mitigated_damage(ctx, damage)
    blocked = min(ctx.defender_block_value, damage)

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
      damage: trunc(mitigated_damage(ctx, damage) * crit_multiplier(ctx)),
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

  defp reconstruct_pre_armor_damage(_ctx, _base_damage, result_damage) when result_damage <= 0, do: 0

  defp reconstruct_pre_armor_damage(ctx, base_damage, result_damage) do
    case mitigated_damage(ctx, base_damage) do
      mitigated when mitigated > 0 -> round(result_damage * base_damage / mitigated)
      _ -> result_damage
    end
  end

  defp glancing_factor(ctx, factor_roll) do
    defense_gap = -ctx.skill_diff
    caster? = ctx.caster_class in [5, 8, 9]
    low = clamp(1.3 - 0.05 * defense_gap - if(caster?, do: 0.7, else: 0.0), 0.01, if(caster?, do: 0.6, else: 0.91))
    high = clamp(1.2 - 0.03 * defense_gap - if(caster?, do: 0.3, else: 0.0), 0.2, 0.99)

    low + (high - low) * clamp(factor_roll, 0.0, 1.0)
  end

  defp avoidance_skill_bonus(%{defender_player?: true} = ctx), do: ctx.avoidance_skill_diff * 0.04
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

  defp physical_school?(mask) when is_integer(mask) and mask > 0, do: (mask &&& 0x1) != 0
  defp physical_school?(_mask), do: true

  defp positive_or(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or(_value, default), do: default

  defp non_negative_or(value, _default) when is_integer(value) and value >= 0, do: value
  defp non_negative_or(_value, default), do: default

  defp bp(chance) when is_number(chance), do: trunc(chance * 100)

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
