defmodule ThistleTea.Game.Spell.CasterState do
  @moduledoc "Control and prevention rules for casting, including immunity spells that escape existing auras."

  import Bitwise, only: [band: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cooldowns
  alias ThistleTea.Game.Spell.Immunity

  def validate(caster, %Spell{} = spell, now, opts \\ []) do
    if Keyword.get(opts, :triggered?, false) or Spell.attribute?(spell, :ignore_caster_and_target_restrictions) do
      :ok
    else
      validate_controls(caster, spell, now)
    end
  end

  defp validate_controls(caster, spell, now) do
    immunity = Immunity.purging(spell)

    case prevented(caster, spell, immunity, now) do
      :ok -> :ok
      error -> if Immunity.empty?(immunity), do: error, else: remaining_controls(caster, spell, immunity)
    end
  end

  defp prevented(caster, spell, immunity, now) do
    error =
      Enum.find_value([{:mod_stun, :stunned}, {:mod_confuse, :confused}, {:mod_fear, :fleeing}], fn {type, reason} ->
        if active_control?(caster, spell, type) and not escapes?(immunity, type), do: {:error, reason}
      end)

    error || prevention_error(caster, spell, AuraLogic.has_aura?(caster, :mod_stun), now)
  end

  defp active_control?(caster, spell, :mod_stun), do: AuraLogic.has_aura?(caster, :mod_stun) and stun_prevents?(spell)
  defp active_control?(caster, _spell, :mod_fear), do: Fear.active?(caster)
  defp active_control?(caster, _spell, type), do: AuraLogic.has_aura?(caster, type)

  defp prevention_error(_caster, %Spell{prevention_type: 1}, true, _now), do: :ok

  defp prevention_error(caster, %Spell{prevention_type: 1} = spell, false, now),
    do: if(silenced?(caster, spell, now), do: {:error, :silenced}, else: :ok)

  defp prevention_error(caster, %Spell{prevention_type: 2}, _stunned?, _now),
    do: if(CombatControl.pacified?(caster), do: {:error, :pacified}, else: :ok)

  defp prevention_error(_caster, _spell, _stunned?, _now), do: :ok

  defp remaining_controls(%{unit: %Unit{auras: holders}} = caster, spell, immunity) when is_list(holders) do
    Enum.find_value(holders, :ok, &remaining_holder(caster, spell, immunity, &1))
  end

  defp remaining_controls(_caster, _spell, _immunity), do: :ok

  defp remaining_holder(caster, spell, immunity, %Holder{} = holder) do
    if not (Immunity.school?(immunity, holder.spell) or Immunity.dispel?(immunity, holder.spell)) do
      Enum.find_value(holder.auras, &remaining_effect(caster, spell, immunity, holder.spell, &1))
    end
  end

  defp remaining_effect(caster, spell, immunity, source_spell, aura) do
    if not immune_effect?(immunity, source_spell, aura), do: control_error(caster, spell, immunity, aura.type)
  end

  defp immune_effect?(immunity, spell, %Aura{index: index, type: type}) do
    Immunity.state?(immunity, type) or Immunity.mechanic?(immunity, spell.mechanic) or
      Enum.any?(spell.effects, &(&1.index == index and Immunity.mechanic?(immunity, &1.mechanic)))
  end

  defp control_error(_caster, _spell, immunity, :mod_stun) do
    if not escapes?(immunity, :mod_stun), do: {:error, :stunned}
  end

  defp control_error(_caster, _spell, immunity, :mod_confuse) do
    if not escapes?(immunity, :mod_confuse), do: {:error, :confused}
  end

  defp control_error(caster, _spell, immunity, :mod_fear) do
    if Fear.active?(caster) and not escapes?(immunity, :mod_fear), do: {:error, :fleeing}
  end

  defp control_error(_caster, %Spell{prevention_type: prevention}, _immunity, type)
       when type in [:mod_silence, :mod_pacify, :mod_pacify_silence] do
    case prevention do
      1 -> {:error, :silenced}
      2 -> {:error, :pacified}
      _ -> nil
    end
  end

  defp control_error(_caster, _spell, _immunity, _type), do: nil

  defp escapes?(immunity, type) do
    Immunity.state?(immunity, type) or Enum.any?(mechanics(type), &Immunity.mechanic?(immunity, &1))
  end

  defp mechanics(:mod_stun), do: [12]
  defp mechanics(:mod_confuse), do: [17, 30]
  defp mechanics(:mod_fear), do: [5]

  defp stun_prevents?(spell), do: (spell.cast_time_ms || 0) == 0 or band(spell.interrupt_flags || 0, 0x02) != 0

  defp silenced?(caster, spell, now),
    do: CombatControl.silenced?(caster) or Cooldowns.school_locked?(caster, Spell.school_mask(spell), now)
end
