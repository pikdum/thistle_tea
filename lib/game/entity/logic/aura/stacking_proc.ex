defmodule ThistleTea.Game.Entity.Logic.Aura.StackingProc do
  @moduledoc """
  Combat-driven stacking trinket auras whose initial counts and linked lifetime
  are not expressed by the spell data.
  """

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.ProcChance
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Proc

  @unstable_power 24_658
  @unstable_power_bonus 24_659
  @ascendance 28_200
  @ascendance_bonus 28_204
  @restless_strength 24_661
  @restless_strength_bonus 24_662
  @brittle_armor 24_574
  @brittle_armor_bonus 24_575
  @mercurial_shield 26_463
  @mercurial_shield_bonus 26_464
  @initial_triggers %{@unstable_power => @unstable_power_bonus, @restless_strength => @restless_strength_bonus}
  @parents %{
    @unstable_power_bonus => @unstable_power,
    @ascendance_bonus => @ascendance,
    @restless_strength_bonus => @restless_strength,
    @brittle_armor_bonus => @brittle_armor,
    @mercurial_shield_bonus => @mercurial_shield
  }
  @parent_ids Map.values(@parents)
  @full_stacks [@unstable_power_bonus, @restless_strength_bonus, @brittle_armor_bonus, @mercurial_shield_bonus]

  def removal_spell(%Spell{id: 24_590}), do: @brittle_armor_bonus
  def removal_spell(%Spell{id: 26_465}), do: @mercurial_shield_bonus
  def removal_spell(_spell), do: nil

  def prepare(%Holder{spell: %Spell{id: @ascendance}} = holder, _existing), do: %{holder | charges: 6}

  def prepare(%Holder{spell: %Spell{id: id}, caster_guid: caster} = holder, existing) when is_map_key(@parents, id) do
    if Enum.any?(
         existing,
         &(Holder.same_source?(&1, Map.fetch!(@parents, id), caster) and Holder.alive?(&1, holder.applied_at))
       ) do
      if id in @full_stacks, do: %{holder | stacks: holder.spell.stack_amount}, else: holder
    end
  end

  def prepare(%Holder{} = holder, _existing), do: holder

  def reconcile(previous, desired) do
    removed_parents =
      previous
      |> Enum.filter(&(&1.spell.id in @parent_ids))
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
    for %Holder{spell: %Spell{id: id}, caster_guid: caster, caster_level: level} <- holders,
        is_map_key(@initial_triggers, id) do
      Effects.trigger_spell(caster, level || 1, caster, Map.fetch!(@initial_triggers, id), triggered_by_spell_id: id)
    end
  end

  def outgoing_proc(holders, %Holder{spell: %Spell{id: @unstable_power_bonus}} = holder, _owner, %{spell: spell}) do
    if unstable_power_spell?(holder, spell) do
      {:handled, spend(holders, holder), []}
    else
      {:handled, holders, []}
    end
  end

  def outgoing_proc(holders, %Holder{spell: %Spell{id: @restless_strength}} = holder, _owner, _context) do
    {:handled, spend_bonus(holders, holder), []}
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

  def outgoing_melee(entity, holders, %Holder{spell: %Spell{id: @restless_strength}} = holder, context) do
    if Proc.eligible?(holder.spell, Map.get(context, :spell), context.proc_type, context) and
         ProcChance.roll?(entity, holder.spell, :outgoing, context) do
      {:handled, spend_bonus(holders, holder), []}
    else
      {:handled, holders, []}
    end
  end

  def outgoing_melee(_entity, _holders, _holder, _context), do: :unhandled

  defp spend_bonus(holders, %Holder{caster_guid: caster}) do
    case Enum.find(holders, &Holder.same_source?(&1, @restless_strength_bonus, caster)) do
      %Holder{} = bonus -> spend(holders, bonus)
      nil -> holders
    end
  end

  defp spend(holders, holder) do
    updated =
      case Holder.spend_stack(holder) do
        nil -> []
        holder -> [holder]
      end

    replace(holders, holder, updated)
  end

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
