defmodule ThistleTea.Game.Entity.Logic.Aura.StackingProc do
  @moduledoc """
  Cast-driven stacking trinket auras whose initial counts and linked lifetime
  are not expressed by the spell data.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @unstable_power 24_658
  @unstable_power_bonus 24_659
  @ascendance 28_200
  @ascendance_bonus 28_204
  @parents %{@unstable_power_bonus => @unstable_power, @ascendance_bonus => @ascendance}

  def prepare(%Holder{spell: %Spell{id: @ascendance}} = holder, _existing), do: %{holder | charges: 6}

  def prepare(%Holder{spell: %Spell{id: id}, caster_guid: caster} = holder, existing) when is_map_key(@parents, id) do
    if Enum.any?(existing, &Holder.same_source?(&1, Map.fetch!(@parents, id), caster)) do
      if id == @unstable_power_bonus, do: %{holder | stacks: holder.spell.stack_amount}, else: holder
    end
  end

  def prepare(%Holder{} = holder, _existing), do: holder

  def reconcile(previous, desired) do
    removed_parents =
      previous
      |> Enum.filter(&(&1.spell.id in [@unstable_power, @ascendance]))
      |> Enum.reject(fn %Holder{} = old ->
        Enum.any?(desired, fn %Holder{} = current ->
          Holder.same_source?(current, old.spell.id, old.caster_guid) and current.applied_at == old.applied_at
        end)
      end)

    Enum.reject(desired, fn %Holder{spell: %Spell{id: id}, caster_guid: caster} ->
      case @parents[id] do
        nil -> false
        parent -> Enum.any?(removed_parents, &Holder.same_source?(&1, parent, caster))
      end
    end)
  end

  def after_apply(holders) do
    for %Holder{spell: %Spell{id: @unstable_power}, caster_guid: caster, caster_level: level} <- holders do
      Effects.trigger_spell(caster, level || 1, caster, @unstable_power_bonus, triggered_by_spell_id: @unstable_power)
    end
  end

  def outgoing_proc(holders, %Holder{spell: %Spell{id: @unstable_power_bonus}} = holder, _owner, %{spell: spell}) do
    if unstable_power_spell?(holder, spell) do
      updated = if holder.stacks > 1, do: [%{holder | stacks: holder.stacks - 1}], else: []
      {:handled, replace(holders, holder, updated), []}
    else
      {:handled, holders, []}
    end
  end

  def outgoing_proc(holders, %Holder{spell: %Spell{id: @ascendance}} = holder, owner, %{spell: spell}) do
    cond do
      Enum.any?(spell.effects, & &1.area_target?) or match?([%Effect{type: :script_effect} | _], spell.effects) ->
        {:handled, holders, []}

      holder.charges <= 1 ->
        {:handled, List.delete(holders, holder), []}

      true ->
        event =
          Effects.trigger_spell(owner, holder.caster_level || 1, owner, @ascendance_bonus,
            triggered_by_spell_id: @ascendance
          )

        {:handled, replace(holders, holder, [%{holder | charges: holder.charges - 1}]), [event]}
    end
  end

  def outgoing_proc(_holders, _holder, _owner, _context), do: :unhandled

  defp unstable_power_spell?(%Holder{auras: auras}, %Spell{} = spell) do
    school? =
      Enum.any?(auras, fn
        %Aura{type: :mod_damage_done, misc_value: mask} -> Bitwise.band(mask, Spell.school_mask(spell)) != 0
        _aura -> false
      end)

    school? and
      (Spell.healing?(spell) or Enum.any?(spell.effects, &damage_effect?/1) or
         {spell.spell_visual, spell.spell_icon} in [{319, 1647}, {221, 680}, {369, 37}, {221, 33}])
  end

  defp damage_effect?(%Effect{type: type})
       when type in [
              :instakill,
              :school_damage,
              :environmental_damage,
              :health_leech,
              :power_burn,
              :weapon_damage,
              :weapon_damage_noschool,
              :normalized_weapon_damage,
              :weapon_percent_damage
            ], do: true

  defp damage_effect?(%Effect{aura: aura}), do: aura in [:periodic_damage, :periodic_leech, :periodic_health_funnel]

  defp replace(holders, holder, replacement) do
    Enum.flat_map(holders, fn current -> if current == holder, do: replacement, else: [current] end)
  end
end
