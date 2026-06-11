defmodule ThistleTea.Game.Spell.CastValidation do
  @moduledoc """
  Pure pre-cast validation shared by every cast entry point: caster alive,
  cooldown ready, sufficient power, reagents on hand, target compatibility
  (hostile/friendly, alive/dead), and range. Target facts are passed in as a
  snapshot built at the boundary, so this module never touches processes or
  the database. Returns `:ok` or `{:error, reason}` where the reason maps to a
  1.12 `SMSG_CAST_RESULT` code.
  """
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Targets

  @power_fields %{0 => :power1, 1 => :power2, 2 => :power3, 3 => :power4, 4 => :power5}
  @range_leeway_yards 5.0

  def validate(caster, %Spell{} = spell, %Targets{} = targets, target_info, now, opts \\ []) do
    with :ok <- check_caster_alive(caster),
         :ok <- check_stronger_rank(caster, spell, targets),
         :ok <- check_mechanic_immunity(caster, spell, targets),
         :ok <- check_cooldown(caster, spell, now),
         :ok <- check_power(caster, spell),
         :ok <- check_reagents(caster, spell, Keyword.get(opts, :count_item)),
         :ok <- check_target(spell, target_info) do
      check_range(caster, spell, target_info)
    end
  end

  defp check_caster_alive(caster) do
    if Core.dead?(caster), do: {:error, :caster_dead}, else: :ok
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

  defp check_cooldown(caster, spell, now) do
    if not godmode?(caster) and Cooldowns.on_cooldown?(caster, spell, now) do
      {:error, :not_ready}
    else
      :ok
    end
  end

  defp check_power(%{unit: unit} = caster, %Spell{mana_cost: cost, power_type: power_type})
       when is_integer(cost) and cost > 0 do
    field = Map.get(@power_fields, power_type)
    power = if is_atom(field), do: Map.get(unit, field)
    power = if is_integer(power), do: power, else: 0

    if godmode?(caster) or power >= cost, do: :ok, else: {:error, :no_power}
  end

  defp check_power(_caster, _spell), do: :ok

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

  defp check_incidental_target(%{} = target_info) do
    if Map.get(target_info, :alive?) == false, do: {:error, :targets_dead}, else: :ok
  end

  defp check_incidental_target(_target_info), do: :ok

  defp check_range(caster, %Spell{range_yards: range}, %{position: {map, x, y, z}})
       when is_number(range) and range > 0 do
    case caster_position(caster) do
      {caster_map, _cx, _cy, _cz} when caster_map != map ->
        {:error, :out_of_range}

      {_map, cx, cy, cz} ->
        if distance({cx, cy, cz}, {x, y, z}) > range + @range_leeway_yards do
          {:error, :out_of_range}
        else
          :ok
        end

      nil ->
        :ok
    end
  end

  defp check_range(_caster, _spell, _target_info), do: :ok

  defp caster_position(%{internal: %{map: map}, movement_block: %{position: {x, y, z, _o}}}) do
    {map, x, y, z}
  end

  defp caster_position(_caster), do: nil

  defp distance({x1, y1, z1}, {x2, y2, z2}) do
    :math.sqrt(:math.pow(x2 - x1, 2) + :math.pow(y2 - y1, 2) + :math.pow(z2 - z1, 2))
  end

  defp self_target?(%{object: %{guid: guid}}, unit_guid), do: unit_guid == guid
  defp self_target?(_caster, _unit_guid), do: false

  defp godmode?(%{internal: internal}), do: Map.get(internal, :godmode) == true
  defp godmode?(_caster), do: false
end
