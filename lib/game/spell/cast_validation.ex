defmodule ThistleTea.Game.Spell.CastValidation do
  @moduledoc """
  Pure pre-cast validation shared by every cast entry point: caster alive,
  cooldown ready, sufficient power, reagents on hand, target compatibility
  (hostile/friendly, alive/dead), and range. Target facts are passed in as a
  snapshot built at the boundary, so this module never touches processes or
  the database. Returns `:ok` or `{:error, reason}` where the reason maps to a
  1.12 `SMSG_CAST_RESULT` code.
  """
  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Hunter
  alias ThistleTea.Game.Entity.Logic.Paladin
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Entity.Logic.Warlock
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.Spell.Targets

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}
  @health_power_type -2
  @range_leeway_yards 5.0

  def validate(caster, %Spell{} = spell, %Targets{} = targets, target_info, now, opts \\ []) do
    with :ok <- check_caster_alive(caster),
         :ok <- check_caster_state(caster, spell, now),
         :ok <- check_combat_state(caster, spell),
         :ok <- check_stance(caster, spell),
         :ok <- check_caster_aura_state(caster, spell, now),
         :ok <- Hunter.validate_reactive(caster, spell, targets.unit_guid, now),
         :ok <- check_combo_target(caster, spell, targets, now),
         :ok <- check_stronger_rank(caster, spell, targets),
         :ok <- check_mechanic_immunity(caster, spell, targets),
         :ok <- check_dispel_immunity(caster, spell, targets),
         :ok <- check_special_aura_requirements(caster, spell),
         :ok <- check_warlock_resources(caster, spell),
         :ok <- check_cooldown(caster, spell, now),
         :ok <- check_power(caster, spell),
         :ok <- check_equipped_item(caster, spell, Keyword.get(opts, :equipped_items, [])),
         :ok <- check_ammo(caster, spell, opts),
         :ok <- Hunter.validate_feed(spell, Keyword.get(opts, :feed_context)),
         :ok <- Warlock.validate_ritual(spell, Keyword.get(opts, :ritual_context)),
         :ok <- check_reagents(caster, spell, Keyword.get(opts, :count_item)),
         :ok <- check_target(spell, target_info),
         :ok <- check_target_power_type(spell, target_info),
         :ok <- check_dispel_target(caster, spell, targets, target_info),
         :ok <- check_creature_type(spell, target_info),
         :ok <- check_position(caster, spell, target_info),
         :ok <- check_target_aura_state(spell, target_info),
         :ok <- check_warlock_target(caster, spell, target_info),
         :ok <- Hunter.validate_tame(caster, spell, target_info),
         :ok <- check_range(caster, spell, target_info) do
      check_line_of_sight(spell, target_info)
    end
  end

  defp check_ammo(caster, spell, opts) do
    if godmode?(caster) do
      :ok
    else
      Hunter.validate_ammo(
        spell,
        Keyword.get(opts, :ammo_id),
        Keyword.get(opts, :ammo_template),
        Keyword.get(opts, :equipped_items, []),
        Keyword.get(opts, :count_item)
      )
    end
  end

  defp check_caster_alive(caster) do
    if Core.dead?(caster), do: {:error, :caster_dead}, else: :ok
  end

  defp check_combat_state(%{internal: %{in_combat: true}}, %Spell{} = spell) do
    if Spell.attribute?(spell, :not_in_combat), do: {:error, :affecting_combat}, else: :ok
  end

  defp check_combat_state(_caster, _spell), do: :ok

  defp check_stance(%{unit: unit}, %Spell{} = spell) do
    Spell.shapeshift_cast_error(spell, unit.shapeshift_form || 0)
  end

  defp check_stance(_caster, _spell), do: :ok

  @aura_state_defense 1
  @aura_state_healthless_20 2
  @healthless_pct 20

  defp check_caster_aura_state(caster, %Spell{caster_aura_state: @aura_state_defense}, now) do
    if Reactive.defense_active?(caster, now), do: :ok, else: {:error, :cant_do_that_yet}
  end

  defp check_caster_aura_state(_caster, _spell, _now), do: :ok

  defp check_combo_target(caster, %Spell{} = spell, %Targets{unit_guid: unit_guid}, now) do
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

  defp check_position(caster, %Spell{} = spell, target_info) do
    cond do
      Spell.attribute?(spell, :from_behind) and not behind_target?(caster, target_info) -> {:error, :not_behind}
      Spell.attribute?(spell, :target_facing_caster) and behind_target?(caster, target_info) -> {:error, :not_infront}
      true -> :ok
    end
  end

  defp behind_target?(%{movement_block: %{position: {caster_x, caster_y, _caster_z, _caster_o}}}, %{
         position: {_map, target_x, target_y, _target_z},
         orientation: target_o
       })
       when is_number(target_o) do
    angle = :math.atan2(caster_y - target_y, caster_x - target_x)
    abs(normalize_angle(angle - target_o)) > :math.pi() / 2
  end

  defp behind_target?(_caster, _target_info), do: false

  defp normalize_angle(angle) do
    two_pi = 2 * :math.pi()
    angle = :math.fmod(angle, two_pi)

    cond do
      angle > :math.pi() -> angle - two_pi
      angle < -:math.pi() -> angle + two_pi
      true -> angle
    end
  end

  defp check_stronger_rank(caster, %Spell{} = spell, %Targets{unit_guid: unit_guid}) do
    if self_target?(caster, unit_guid) and AuraLogic.blocked_by_stronger_rank?(caster, spell) do
      {:error, :aura_bounced}
    else
      :ok
    end
  end

  defp check_mechanic_immunity(caster, %Spell{} = spell, %Targets{unit_guid: unit_guid}) do
    if self_target?(caster, unit_guid) and AuraLogic.mechanic_immune?(caster, spell) do
      {:error, :immune}
    else
      :ok
    end
  end

  defp check_dispel_immunity(caster, %Spell{} = spell, %Targets{unit_guid: unit_guid}) do
    if self_target?(caster, unit_guid) and AuraLogic.dispel_immune?(caster, spell) do
      {:error, :immune}
    else
      :ok
    end
  end

  defp check_special_aura_requirements(caster, %Spell{} = spell) do
    if Scripts.paladin_judgement?(spell) and not Paladin.active_seal?(caster) do
      {:error, :cant_do_that_yet}
    else
      :ok
    end
  end

  defp check_warlock_resources(caster, %Spell{} = spell) do
    if Warlock.life_tap?(spell) and (caster.unit.health || 0) <= Warlock.life_tap_cost(spell) do
      {:error, :fizzle}
    else
      :ok
    end
  end

  defp check_cooldown(caster, spell, now) do
    cond do
      godmode?(caster) -> :ok
      Cooldowns.on_cooldown?(caster, spell, now) -> {:error, :not_ready}
      Cooldowns.on_gcd?(caster, spell, now) -> {:error, :not_ready}
      true -> :ok
    end
  end

  @mechanic_fear 5
  @mechanic_stun 12
  @confuse_mechanics [17, 30]

  defp check_caster_state(caster, %Spell{} = spell, now) do
    stunned? = AuraLogic.has_aura?(caster, :mod_stun)

    case control_state_error(caster, spell, stunned?) do
      :ok -> prevention_error(caster, spell, stunned?, now)
      error -> error
    end
  end

  defp control_state_error(caster, spell, stunned?) do
    immune = immunity_purge_mechanics(spell)

    cond do
      stunned? and @mechanic_stun not in immune ->
        {:error, :stunned}

      AuraLogic.has_aura?(caster, :mod_confuse) and Enum.all?(@confuse_mechanics, &(&1 not in immune)) ->
        {:error, :confused}

      AuraLogic.has_aura?(caster, :mod_fear) and @mechanic_fear not in immune ->
        {:error, :fleeing}

      true ->
        :ok
    end
  end

  defp prevention_error(caster, spell, stunned?, now) do
    cond do
      spell.prevention_type == 1 and not stunned? and silenced_for?(caster, spell, now) ->
        {:error, :silenced}

      spell.prevention_type == 2 and AuraLogic.has_aura?(caster, :mod_pacify) ->
        {:error, :pacified}

      true ->
        :ok
    end
  end

  defp silenced_for?(caster, %Spell{} = spell, now) do
    AuraLogic.has_aura?(caster, :mod_silence) or
      Cooldowns.school_locked?(caster, Spell.school_mask(spell), now)
  end

  defp immunity_purge_mechanics(%Spell{effects: effects} = spell) do
    if Spell.attribute?(spell, :immunity_purges_effect) do
      for %Effect{type: type, aura: :mechanic_immunity, misc_value: misc} <- effects,
          type in [:apply_aura, :apply_area_aura],
          is_integer(misc),
          do: misc
    else
      []
    end
  end

  defp check_power(%{unit: unit} = caster, %Spell{power_type: @health_power_type} = spell) do
    cost = Resources.power_cost(caster, spell)
    if godmode?(caster) or (unit.health || 0) > cost, do: :ok, else: {:error, :no_power}
  end

  defp check_power(%{unit: unit} = caster, %Spell{power_type: power_type} = spell) do
    cost = Resources.power_cost(caster, spell)
    field = Map.get(@power_fields, power_type)
    power = if field, do: Map.get(unit, field)
    power = if is_integer(power), do: power, else: 0

    if godmode?(caster) or power >= cost, do: :ok, else: {:error, :no_power}
  end

  defp check_power(_caster, _spell), do: :ok

  defp check_equipped_item(caster, %Spell{equipped_item_class: class} = spell, equipped_items)
       when is_integer(class) and class >= 0 and is_list(equipped_items) do
    if godmode?(caster) or Enum.any?(equipped_items, &item_fits_requirement?(&1, spell)) do
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

  defp check_target(%Spell{} = spell, target_info) do
    cond do
      Spell.resurrect_spell?(spell) -> check_resurrect_target(target_info)
      Spell.requires_hostile_target?(spell) -> check_hostile_target(target_info)
      Spell.requires_friendly_target?(spell) -> check_friendly_target(target_info)
      true -> check_incidental_target(target_info)
    end
  end

  defp check_dispel_target(caster, %Spell{} = spell, %Targets{unit_guid: unit_guid}, target_info) do
    dispel_types =
      spell.effects
      |> Enum.filter(&match?(%{type: :dispel}, &1))
      |> MapSet.new(& &1.misc_value)

    if MapSet.size(dispel_types) == 0 do
      :ok
    else
      options = target_dispel_options(caster, unit_guid, target_info)
      polarity = if match?(%{friendly?: false}, target_info), do: :positive, else: :negative
      check_dispel_options(options, dispel_types, polarity)
    end
  end

  defp check_target_power_type(%Spell{effects: effects}, %{power_type: target_power_type})
       when is_integer(target_power_type) do
    required_types =
      effects
      |> Enum.filter(&(&1.type in [:power_burn, :power_drain]))
      |> Enum.map(& &1.misc_value)

    if required_types == [] or target_power_type in required_types, do: :ok, else: {:error, :bad_targets}
  end

  defp check_target_power_type(_spell, _target_info), do: :ok

  defp target_dispel_options(caster, unit_guid, target_info) do
    if self_target?(caster, unit_guid), do: AuraLogic.dispel_options(caster), else: dispel_options(target_info)
  end

  defp check_dispel_options(options, dispel_types, polarity) do
    matching? =
      Enum.any?(options, fn {type, option_polarity} ->
        MapSet.member?(dispel_types, type) and option_polarity == polarity
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
  defp check_hostile_target(:unknown), do: {:error, :bad_targets}

  defp check_hostile_target(%{} = target_info) do
    cond do
      Map.get(target_info, :alive?) == false -> {:error, :targets_dead}
      Map.get(target_info, :friendly?) == true -> {:error, :target_friendly}
      Map.get(target_info, :attackable?) == false -> {:error, :bad_targets}
      true -> :ok
    end
  end

  defp check_friendly_target(%{} = target_info) do
    cond do
      Map.get(target_info, :alive?) == false -> {:error, :targets_dead}
      Map.get(target_info, :hostile?) == true -> {:error, :target_enemy}
      true -> :ok
    end
  end

  defp check_friendly_target(_target_info), do: :ok

  defp check_creature_type(%Spell{target_creature_type_mask: mask}, _target_info) when mask in [0, nil], do: :ok

  defp check_creature_type(%Spell{} = spell, target_info) when target_info in [nil, :self] do
    if area_target_spell?(spell), do: :ok, else: {:error, :bad_targets}
  end

  defp check_creature_type(%Spell{} = spell, %{creature_type: creature_type}) do
    if Spell.creature_type_allowed?(spell, creature_type), do: :ok, else: {:error, :bad_targets}
  end

  defp check_creature_type(%Spell{}, _target_info), do: {:error, :bad_targets}

  defp area_target_spell?(%Spell{effects: effects}) do
    Enum.any?(effects, fn effect ->
      effect.implicit_target_a in [:aoe_enemy_at_caster, :aoe_enemy_in_cone, :aoe_enemy_at_dest] or
        effect.implicit_target_b in [:aoe_enemy_at_caster, :aoe_enemy_in_cone, :aoe_enemy_at_dest]
    end)
  end

  defp check_incidental_target(%{} = target_info) do
    if Map.get(target_info, :alive?) == false, do: {:error, :targets_dead}, else: :ok
  end

  defp check_incidental_target(_target_info), do: :ok

  defp check_range(caster, %Spell{range_yards: range} = spell, %{position: {map, x, y, z}})
       when is_number(range) and range > 0 do
    case caster_position(caster) do
      {caster_map, _cx, _cy, _cz} when caster_map != map ->
        {:error, :out_of_range}

      {_map, cx, cy, cz} ->
        check_distance(distance({cx, cy, cz}, {x, y, z}), spell)

      nil ->
        :ok
    end
  end

  defp check_range(_caster, _spell, _target_info), do: :ok

  defp check_distance(distance, %Spell{range_yards: range, min_range_yards: min_range}) do
    cond do
      distance > range + @range_leeway_yards -> {:error, :out_of_range}
      is_number(min_range) and min_range > 0 and distance < min_range -> {:error, :too_close}
      true -> :ok
    end
  end

  defp check_line_of_sight(%Spell{} = spell, %{los?: false}) do
    if Spell.attribute?(spell, :ignore_line_of_sight) do
      :ok
    else
      {:error, :line_of_sight}
    end
  end

  defp check_line_of_sight(_spell, _target_info), do: :ok

  defp caster_position(%{internal: %{world: world}, movement_block: %{position: {x, y, z, _o}}}) do
    {world, x, y, z}
  end

  defp caster_position(_caster), do: nil

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2) + :math.pow(z2 - z1, 2))
  end

  defp self_target?(%{object: %{guid: guid}}, unit_guid), do: unit_guid == guid
  defp self_target?(_caster, _unit_guid), do: false

  defp godmode?(%{internal: internal}), do: internal.godmode == true
  defp godmode?(_caster), do: false
end
