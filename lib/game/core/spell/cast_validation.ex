defmodule ThistleTea.Game.Core.Spell.CastValidation do
  @moduledoc """
  Pure pre-cast validation shared by every cast entry point: caster alive,
  cooldown ready, sufficient power, reagents on hand, target compatibility
  (hostile/friendly, alive/dead), and range. Target facts are passed in as a
  snapshot built at the boundary, so this module never touches processes or
  the database. Returns `:ok` or `{:error, reason}` where the reason maps to a
  1.12 `SMSG_CAST_RESULT` code.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Core.Aura, as: AuraLogic
  alias ThistleTea.Game.Core.Aura.Dispel
  alias ThistleTea.Game.Core.Aura.EffectImmunity
  alias ThistleTea.Game.Core.Aura.Invulnerability
  alias ThistleTea.Game.Core.Aura.Shapeshift
  alias ThistleTea.Game.Core.Battleground.Insignia
  alias ThistleTea.Game.Core.Class.Druid
  alias ThistleTea.Game.Core.Class.Hunter
  alias ThistleTea.Game.Core.Class.Paladin
  alias ThistleTea.Game.Core.Class.Warlock
  alias ThistleTea.Game.Core.Combat.Disarm
  alias ThistleTea.Game.Core.Combat.Hostility
  alias ThistleTea.Game.Core.Combat.Reactive
  alias ThistleTea.Game.Core.Duel
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Item.Ammunition
  alias ThistleTea.Game.Core.Item.Enchantments
  alias ThistleTea.Game.Core.Loot.Pickpocket
  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.Core.Power.Resources
  alias ThistleTea.Game.Core.Profession.Disenchant
  alias ThistleTea.Game.Core.Profession.OpenLock
  alias ThistleTea.Game.Core.Profession.Skinning
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Area
  alias ThistleTea.Game.Core.Spell.AuraRank
  alias ThistleTea.Game.Core.Spell.Battleground
  alias ThistleTea.Game.Core.Spell.CasterState
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.CorpseTarget
  alias ThistleTea.Game.Core.Spell.Destination
  alias ThistleTea.Game.Core.Spell.Environment
  alias ThistleTea.Game.Core.Spell.Facing
  alias ThistleTea.Game.Core.Spell.Focus
  alias ThistleTea.Game.Core.Spell.Immunity
  alias ThistleTea.Game.Core.Spell.LocationTargets
  alias ThistleTea.Game.Core.Spell.Mount
  alias ThistleTea.Game.Core.Spell.ObjectTargets
  alias ThistleTea.Game.Core.Spell.Posture
  alias ThistleTea.Game.Core.Spell.Range
  alias ThistleTea.Game.Core.Spell.Scripts
  alias ThistleTea.Game.Core.Spell.StackRules
  alias ThistleTea.Game.Core.Spell.Stealth
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.UnitTargets

  def validate(caster, %Spell{} = spell, %Target{} = targets, target_info, now, opts \\ []) do
    with :ok <- check_caster_alive(caster),
         :ok <- Posture.validate(caster, spell, opts),
         :ok <- check_spirit_of_redemption(caster, spell),
         :ok <- CasterState.validate(caster, spell, now, opts),
         :ok <- check_combat_state(caster, spell),
         :ok <- Stealth.validate(caster, spell, opts),
         :ok <- check_peaceful_target(spell, target_info, opts),
         :ok <- AuraRank.validate(caster, spell, target_info, opts),
         :ok <- Battleground.validate(spell, Keyword.get(opts, :battleground)),
         :ok <- Area.validate(spell, Keyword.get(opts, :spell_area)),
         :ok <- Environment.validate(caster, spell, Keyword.get(opts, :outdoors?)),
         :ok <- Pickpocket.validate(caster, spell, target_info),
         :ok <- Skinning.validate(caster, spell, target_info, opts),
         :ok <- OpenLock.validate(caster, spell, Keyword.get(opts, :lock_context)),
         :ok <- Disenchant.validate(caster, spell, Keyword.get(opts, :disenchant_item)),
         :ok <-
           Enchantments.validate(
             caster,
             spell,
             Keyword.get(opts, :enchant_item),
             Keyword.get(opts, :enchant_ownership, :owned)
           ),
         :ok <- check_tools(spell, Keyword.get(opts, :count_item)),
         :ok <- Focus.validate(caster, spell, Keyword.get(opts, :spell_focus)),
         :ok <- ObjectTargets.validate(spell, Keyword.get(opts, :spell_objects)),
         :ok <- Mount.validate(caster, spell, opts),
         :ok <- check_stance(caster, spell),
         :ok <- check_caster_aura_state(caster, spell, now),
         :ok <- Hunter.validate_reactive(caster, spell, Target.unit_guid(targets), now),
         :ok <- check_combo_target(caster, spell, targets, now),
         :ok <- check_stronger_rank(caster, spell, targets),
         :ok <- check_stronger_group(caster, spell, targets, target_info),
         :ok <- check_mechanic_immunity(caster, spell, targets, target_info),
         :ok <- check_dispel_immunity(caster, spell, targets),
         :ok <- check_protection_immunity(caster, spell, targets, target_info),
         :ok <- check_special_aura_requirements(caster, spell),
         :ok <- check_warlock_resources(caster, spell),
         :ok <- check_cooldown(caster, spell, now),
         :ok <- check_power(caster, spell, opts),
         :ok <- Disarm.validate(caster, spell),
         :ok <- check_equipped_item(caster, spell, Keyword.get(opts, :equipped_items, [])),
         :ok <- check_ammo(caster, spell, opts),
         :ok <- Hunter.validate_feed(spell, Keyword.get(opts, :feed_context)),
         :ok <- Hunter.validate_companion(caster, spell),
         :ok <- Warlock.validate_ritual(spell, Keyword.get(opts, :ritual_context)),
         :ok <- check_reagents(caster, spell, Keyword.get(opts, :count_item)),
         :ok <- check_duel(spell, Keyword.get(opts, :duel_context)),
         :ok <- CorpseTarget.validate(spell, Keyword.get(opts, :spell_corpse)),
         :ok <- Destination.validate(caster, spell, targets, Keyword.get(opts, :destination_los?), opts) do
      if CorpseTarget.required?(spell), do: :ok, else: validate_target(caster, spell, targets, target_info, opts)
    end
  end

  def validate_target(caster, %Spell{} = spell, %Target{} = targets, target_info, opts \\ []) do
    cond do
      Insignia.spell?(spell) ->
        Insignia.validate(caster, target_info)

      UnitTargets.required?(spell) or LocationTargets.required?(spell) ->
        validate_explicit_effects(caster, spell, targets, target_info, opts)

      true ->
        validate_unit_target(caster, spell, targets, target_info, opts)
    end
  end

  defp validate_explicit_effects(caster, spell, targets, target_info, opts) do
    effects =
      Enum.filter(spell.effects, fn effect ->
        not UnitTargets.scripted?(effect) and effect.implicit_target_a != :script_location_near_caster and
          Enum.any?(
            [effect.implicit_target_a, effect.implicit_target_b],
            &(&1 in [:target_enemy, :target_ally, :any_unit, :party_member, :enemy_location, :unit_location])
          )
      end)

    if effects == [],
      do: :ok,
      else: validate_unit_target(caster, %{spell | effects: effects}, targets, target_info, opts)
  end

  defp validate_unit_target(caster, spell, targets, target_info, opts) do
    with :ok <- check_target_flags(caster, spell, target_info),
         :ok <- Shapeshift.validate_target(caster, spell, target_info),
         :ok <- check_target(spell, target_info),
         :ok <- check_target_power_type(spell, targets, target_info),
         :ok <- check_dispel_target(caster, spell, targets, target_info),
         :ok <- check_creature_type(spell, target_info),
         :ok <- Facing.validate(caster, spell, target_info, opts),
         :ok <- check_target_aura_state(spell, target_info),
         :ok <- check_warlock_target(caster, spell, target_info),
         :ok <- Druid.validate_target(caster, spell, target_info),
         :ok <- PlayerPossession.validate(caster, spell, target_info),
         :ok <- Hunter.validate_tame(caster, spell, target_info),
         :ok <- Range.validate(caster, spell, target_info, opts) do
      check_line_of_sight(spell, target_info)
    end
  end

  def channel_in_range?(caster, %Spell{range_yards: range} = spell, target_info) when is_number(range) and range > 0 do
    hostile? = Map.get(target_info, :hostile?, Spell.harmful?(spell))

    max_range = Range.channel_maximum(caster, spell, hostile?)

    case Range.combat_distance(caster, target_info) do
      {:ok, distance} -> distance <= max_range
      :different_world -> false
      :unknown -> true
    end
  end

  def channel_in_range?(_caster, _spell, _target_info), do: true

  defp check_duel(%Spell{} = spell, context) do
    if Spell.duel?(spell), do: validate_duel_context(context), else: :ok
  end

  defp validate_duel_context(context) do
    case Duel.validate_admission(context) do
      :ok -> :ok
      {:error, reason} when reason in [:initiator_busy, :opponent_busy] -> {:error, :target_dueling}
      {:error, :no_dueling} -> {:error, :no_dueling}
      {:error, _reason} -> {:error, :bad_targets}
    end
  end

  defp check_ammo(caster, spell, opts) do
    if godmode?(caster) do
      :ok
    else
      Ammunition.validate(
        spell,
        Keyword.get(opts, :ammo_id),
        Keyword.get(opts, :ammo_template),
        Keyword.get(opts, :equipped_items, []),
        Keyword.get(opts, :count_item)
      )
    end
  end

  defp check_caster_alive(caster) do
    if Entity.dead?(caster), do: {:error, :caster_dead}, else: :ok
  end

  defp check_spirit_of_redemption(caster, %Spell{} = spell) do
    if AuraLogic.has_spell?(caster, 27_827) and not Spell.healing?(spell) do
      {:error, :not_shapeshift}
    else
      :ok
    end
  end

  defp check_combat_state(%{internal: %{in_combat: true}}, %Spell{} = spell) do
    if Spell.attribute?(spell, :not_in_combat), do: {:error, :affecting_combat}, else: :ok
  end

  defp check_combat_state(_caster, _spell), do: :ok

  defp check_peaceful_target(spell, %{unit_flags: flags}, opts) when is_integer(flags) do
    if Spell.attribute?(spell, :only_peaceful_targets) and not Keyword.get(opts, :triggered?, false) and
         (flags &&& 0x00080000) != 0,
       do: {:error, :target_in_combat},
       else: :ok
  end

  defp check_peaceful_target(_spell, _target, _opts), do: :ok

  defp check_stance(%{unit: unit}, %Spell{} = spell) do
    Spell.shapeshift_cast_error(spell, unit.shapeshift_form || 0)
  end

  defp check_stance(_caster, _spell), do: :ok

  @aura_state_defense 1
  @aura_state_healthless_20 2
  @aura_state_hunter_parry 7
  @healthless_pct 20

  defp check_caster_aura_state(caster, %Spell{caster_aura_state: @aura_state_defense}, now) do
    if Reactive.defense_active?(caster, now), do: :ok, else: {:error, :cant_do_that_yet}
  end

  defp check_caster_aura_state(caster, %Spell{caster_aura_state: @aura_state_hunter_parry}, now) do
    if Reactive.active?(caster, :hunter_parry, now), do: :ok, else: {:error, :cant_do_that_yet}
  end

  defp check_caster_aura_state(_caster, _spell, _now), do: :ok

  defp check_combo_target(caster, %Spell{} = spell, %Target{} = targets, now) do
    unit_guid = Target.unit_guid(targets)

    if Scripts.requires_combo_target?(spell) and not Reactive.combo_active?(caster, unit_guid, now) do
      {:error, :cant_do_that_yet}
    else
      :ok
    end
  end

  defp check_combo_target(_caster, _spell, _targets, _now), do: :ok

  defp check_target_aura_state(%Spell{target_aura_state: @aura_state_healthless_20}, target_info) do
    case target_info do
      %{health_pct: pct} when is_number(pct) and pct < @healthless_pct -> :ok
      _ -> {:error, :target_aurastate}
    end
  end

  defp check_target_aura_state(_spell, _target_info), do: :ok

  defp check_warlock_target(%{object: %{guid: caster_guid}}, %Spell{} = spell, %{aura_sources: sources}) do
    if Warlock.conflagrate?(spell) and not Warlock.immolate_source?(sources, caster_guid) do
      {:error, :target_aurastate}
    else
      :ok
    end
  end

  defp check_warlock_target(_caster, %Spell{} = spell, _target_info) do
    if Warlock.conflagrate?(spell), do: {:error, :target_aurastate}, else: :ok
  end

  defp check_stronger_rank(caster, %Spell{} = spell, %Target{} = targets) do
    unit_guid = Target.unit_guid(targets)

    if self_target?(caster, unit_guid) and AuraLogic.blocked_by_stronger_rank?(caster, spell) do
      {:error, :aura_bounced}
    else
      :ok
    end
  end

  defp check_stronger_group(caster, spell, targets, target_info) do
    sources =
      cond do
        self_target?(caster, Target.unit_guid(targets)) -> AuraLogic.source_spells(caster)
        is_map(target_info) -> Map.get(target_info, :aura_sources, MapSet.new())
        true -> MapSet.new()
      end

    StackRules.validate(spell, sources)
  end

  defp check_mechanic_immunity(caster, %Spell{} = spell, %Target{} = targets, target_info) do
    unit_guid = Target.unit_guid(targets)

    immune? =
      if self_target?(caster, unit_guid),
        do: AuraLogic.mechanic_immune?(caster, spell),
        else: target_mechanic_immune?(target_info, spell)

    if immune? do
      {:error, if(Spell.harmful?(spell), do: :immune, else: :target_aurastate)}
    else
      :ok
    end
  end

  defp target_mechanic_immune?(%{friendly_mechanic_immunities: mechanics}, spell),
    do: EffectImmunity.blocks_friendly_mechanic?(mechanics, spell)

  defp target_mechanic_immune?(_target_info, _spell), do: false

  defp check_dispel_immunity(caster, %Spell{} = spell, %Target{} = targets) do
    unit_guid = Target.unit_guid(targets)

    if self_target?(caster, unit_guid) and AuraLogic.dispel_immune?(caster, spell) do
      {:error, :immune}
    else
      :ok
    end
  end

  defp check_protection_immunity(caster, spell, targets, target_info) do
    carrier? =
      if self_target?(caster, Target.unit_guid(targets)),
        do: Invulnerability.carrier?(caster),
        else: is_map(target_info) and Map.get(target_info, :invulnerability_interruptible?, false)

    if carrier? and Immunity.targeted_school_protection?(spell), do: {:error, :target_aurastate}, else: :ok
  end

  defp check_special_aura_requirements(caster, %Spell{} = spell) do
    if Scripts.paladin_judgement?(spell) and not Paladin.active_seal?(caster) do
      {:error, :cant_do_that_yet}
    else
      :ok
    end
  end

  defp check_warlock_resources(caster, %Spell{} = spell) do
    if Warlock.life_tap?(spell) and (caster.unit.health || 0) <= Warlock.life_tap_cost(caster, spell) do
      {:error, :fizzle}
    else
      :ok
    end
  end

  defp check_cooldown(caster, spell, now) do
    cond do
      godmode?(caster) -> :ok
      Cooldowns.on_cooldown?(caster, spell, now) -> cooldown_error(spell)
      Cooldowns.on_gcd?(caster, spell, now) -> cooldown_error(spell)
      true -> :ok
    end
  end

  defp cooldown_error(%Spell{} = spell) do
    {:error, if(Spell.attribute?(spell, :cooldown_on_event), do: :dont_report, else: :not_ready)}
  end

  defp check_power(caster, spell, opts) do
    Resources.validate_cast_cost(caster, spell.power_type, Resources.power_cost(caster, spell, opts))
  end

  defp check_equipped_item(%Mob{}, _spell, _equipped_items), do: :ok

  defp check_equipped_item(caster, %Spell{equipped_item_class: class} = spell, equipped_items)
       when is_integer(class) and class >= 0 and is_list(equipped_items) do
    if Enchantments.item_enchant?(spell) or godmode?(caster) or
         Enum.any?(equipped_items, &item_fits_requirement?(&1, spell)) do
      :ok
    else
      {:error, :equipped_item_class}
    end
  end

  defp check_equipped_item(_caster, _spell, _equipped_items), do: :ok

  defp item_fits_requirement?(%{class: item_class, subclass: subclass}, %Spell{
         equipped_item_class: class,
         equipped_item_subclass_mask: mask
       })
       when is_integer(item_class) and is_integer(subclass) do
    item_class == class and (mask == 0 or (mask &&& 1 <<< subclass) != 0)
  end

  defp item_fits_requirement?(_item, _spell), do: false

  defp check_reagents(caster, %Spell{reagents: [_ | _] = reagents}, count_item) when is_function(count_item, 1) do
    enough? =
      godmode?(caster) or
        Enum.all?(reagents, fn {item_id, count} -> count_item.(item_id) >= count end)

    if enough?, do: :ok, else: {:error, :reagents}
  end

  defp check_reagents(_caster, _spell, _count_item), do: :ok

  defp check_tools(%Spell{tools: tools}, count_item) when is_function(count_item, 1) do
    if Enum.all?(tools, &(count_item.(&1) > 0)), do: :ok, else: {:error, :item_gone}
  end

  defp check_tools(_spell, _count_item), do: :ok

  defp check_target_flags(%{object: %{guid: guid}}, _spell, %{guid: guid}), do: :ok

  defp check_target_flags(caster, spell, target_info) when is_map(target_info) do
    if Hostility.targetable_by?(caster, target_info, not Spell.harmful?(spell)), do: :ok, else: {:error, :bad_targets}
  end

  defp check_target_flags(_caster, _spell, _target_info), do: :ok

  defp check_target(%Spell{}, %{visible?: false}), do: {:error, :bad_targets}
  defp check_target(%Spell{}, :unknown), do: {:error, :bad_targets}

  defp check_target(%Spell{} = spell, target_info) do
    cond do
      Skinning.spell?(spell) ->
        :ok

      Spell.resurrect_spell?(spell) ->
        check_resurrect_target(target_info)

      match?(%{alive?: false}, target_info) and not Spell.attribute?(spell, :allow_dead_target) ->
        {:error, :targets_dead}

      Spell.requires_hostile_target?(spell) ->
        check_hostile_target(target_info)

      Spell.requires_friendly_target?(spell) ->
        check_friendly_target(target_info)

      true ->
        :ok
    end
  end

  defp check_dispel_target(caster, %Spell{} = spell, %Target{} = targets, target_info) do
    unit_guid = Target.unit_guid(targets)

    dispel_types =
      spell.effects
      |> Enum.filter(&match?(%{type: :dispel}, &1))
      |> MapSet.new(& &1.misc_value)

    if MapSet.size(dispel_types) == 0 or not single_target_dispel?(spell) do
      :ok
    else
      options = target_dispel_options(caster, unit_guid, target_info)
      polarity = if match?(%{friendly?: false}, target_info), do: :positive, else: :negative
      check_dispel_options(options, dispel_types, polarity)
    end
  end

  defp single_target_dispel?(%Spell{effects: effects}) do
    Enum.all?(effects, fn effect -> effect.type == :dispel and effect.radius_yards in [nil, 0, 0.0] end)
  end

  defp check_target_power_type(%Spell{} = spell, %Target{} = targets, %{guid: target_guid} = target_info) do
    if Target.unit_guid(targets) == target_guid do
      validate_target_power_type(spell, target_info)
    else
      :ok
    end
  end

  defp check_target_power_type(_spell, _targets, _target_info), do: :ok

  defp validate_target_power_type(%Spell{effects: effects}, %{power_type: target_power_type})
       when is_integer(target_power_type) do
    required_types =
      effects
      |> Enum.filter(&(&1.type in [:power_burn, :power_drain]))
      |> Enum.map(& &1.misc_value)

    if required_types == [] or target_power_type in required_types, do: :ok, else: {:error, :bad_targets}
  end

  defp validate_target_power_type(_spell, _target_info), do: :ok

  defp target_dispel_options(caster, unit_guid, target_info) do
    if self_target?(caster, unit_guid), do: AuraLogic.dispel_options(caster), else: dispel_options(target_info)
  end

  defp check_dispel_options(options, dispel_types, polarity) do
    matching? =
      Enum.any?(options, fn {type, option_polarity} ->
        Enum.any?(dispel_types, fn dispel_type ->
          Dispel.matches?(type, option_polarity, dispel_type, polarity)
        end)
      end)

    if matching?, do: :ok, else: {:error, :nothing_to_dispel}
  end

  defp dispel_options(%{dispel_options: %MapSet{} = options}), do: options
  defp dispel_options(_target_info), do: MapSet.new()

  defp check_resurrect_target(%{} = target_info) do
    cond do
      Map.get(target_info, :alive?) == true -> {:error, :target_not_dead}
      Map.get(target_info, :hostile?) == true -> {:error, :target_enemy}
      true -> :ok
    end
  end

  defp check_resurrect_target(_target_info), do: {:error, :bad_targets}

  defp check_hostile_target(nil), do: {:error, :bad_implicit_targets}
  defp check_hostile_target(:self), do: {:error, :bad_targets}

  defp check_hostile_target(%{} = target_info) do
    cond do
      Map.get(target_info, :friendly?) == true -> {:error, :target_friendly}
      Map.get(target_info, :attackable?) == false -> {:error, :bad_targets}
      true -> :ok
    end
  end

  defp check_friendly_target(%{} = target_info) do
    cond do
      Map.get(target_info, :hostile?) == true -> {:error, :target_enemy}
      Map.get(target_info, :helpful?) == false -> {:error, :bad_targets}
      true -> :ok
    end
  end

  defp check_friendly_target(_target_info), do: :ok

  defp check_creature_type(%Spell{} = spell, target_info) do
    if Spell.creature_type_mask_ignored?(spell), do: :ok, else: validate_creature_type(spell, target_info)
  end

  defp validate_creature_type(%Spell{target_creature_type_mask: mask}, _target_info) when mask in [0, nil], do: :ok

  defp validate_creature_type(%Spell{} = spell, target_info) when target_info in [nil, :self] do
    if area_target_spell?(spell), do: :ok, else: {:error, :bad_targets}
  end

  defp validate_creature_type(%Spell{} = spell, %{creature_type: creature_type}) do
    if Spell.creature_type_allowed?(spell, creature_type), do: :ok, else: {:error, :bad_targets}
  end

  defp validate_creature_type(%Spell{}, _target_info), do: {:error, :bad_targets}

  defp area_target_spell?(%Spell{effects: effects}) do
    area_targets = [
      :aoe_enemy_at_caster,
      :aoe_enemy_in_cone,
      :aoe_enemy_at_dest,
      :aoe_ally_at_source,
      :aoe_ally_at_dest
    ]

    Enum.any?(effects, fn effect ->
      effect.implicit_target_a in area_targets or effect.implicit_target_b in area_targets
    end)
  end

  defp check_line_of_sight(%Spell{} = spell, %{los?: false}) do
    if Spell.attribute?(spell, :ignore_line_of_sight) do
      :ok
    else
      {:error, :line_of_sight}
    end
  end

  defp check_line_of_sight(_spell, _target_info), do: :ok

  defp self_target?(%{object: %{guid: guid}}, unit_guid), do: unit_guid == guid
  defp self_target?(_caster, _unit_guid), do: false

  defp godmode?(%{internal: internal}), do: internal.godmode == true
  defp godmode?(_caster), do: false
end
