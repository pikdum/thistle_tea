defmodule ThistleTea.Game.Entity.Logic.Aura do
  @moduledoc """
  Facade over the aura subsystem, split by concern: `Application` (holder
  construction and stacking/immunity rules), `Lifecycle` (expiry, interrupt
  and explicit removal, dispel), `Periodic` (DoT/HoT/trigger ticking),
  `Reactions` (on-hit procs and charges), `Absorption` (damage and mana
  shields), and the `UnitSync`/`MovementSync` derivations. Queries over the
  active holders live here.
  """
  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.Absorption
  alias ThistleTea.Game.Entity.Logic.Aura.Application, as: AuraApplication
  alias ThistleTea.Game.Entity.Logic.Aura.Lifecycle
  alias ThistleTea.Game.Entity.Logic.Aura.Periodic
  alias ThistleTea.Game.Entity.Logic.Aura.Reactions
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Spell

  defdelegate apply_spell(entity, context, spell, now), to: AuraApplication
  defdelegate apply_spell(entity, caster_guid, caster_level, spell, now), to: AuraApplication
  defdelegate blocked_by_stronger_rank?(entity_or_holders, spell), to: AuraApplication
  defdelegate mechanic_immune?(entity, spell), to: AuraApplication

  defdelegate interrupt_mask(action), to: Lifecycle
  defdelegate self_duration_events(entity, now), to: Lifecycle
  defdelegate expire_due(entity, now), to: Lifecycle
  defdelegate remove_with_interrupt_flags(entity, mask, now), to: Lifecycle
  defdelegate remove_spells(entity, spell_ids, now), to: Lifecycle
  defdelegate cancel_spell(entity, spell_id, now), to: Lifecycle
  defdelegate dispel(entity, dispel_type, now, polarity \\ nil), to: Lifecycle
  defdelegate break_on_damage(entity, now), to: Lifecycle

  defdelegate tick(entity, now), to: Periodic
  defdelegate next_event_at(entity), to: Periodic

  defdelegate reactions(entity, event, context), to: Reactions

  defdelegate absorb_damage(entity, damage, school), to: Absorption

  defdelegate sync_unit(unit), to: UnitSync

  def flat_modifier(%{unit: %Unit{auras: holders}}, type, school_mask) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} = holder -> Enum.map(auras, &{&1, holder_stacks(holder)}) end)
    |> Enum.reduce(0, fn
      {%Aura{type: ^type, amount: amount, misc_value: misc}, stacks}, acc
      when is_integer(amount) and is_integer(misc) ->
        if Bitwise.band(misc, school_mask) == 0, do: acc, else: acc + amount * stacks

      _aura, acc ->
        acc
    end)
  end

  def flat_modifier(_entity, _type, _school_mask), do: 0

  def percent_multiplier(%{unit: %Unit{auras: holders}}, type, school_mask) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.reduce(1.0, fn
      %Aura{type: ^type, amount: amount, misc_value: misc}, acc
      when is_integer(amount) and is_integer(misc) ->
        if Bitwise.band(misc, school_mask) == 0, do: acc, else: acc * max(100 + amount, 0) / 100

      _aura, acc ->
        acc
    end)
  end

  def percent_multiplier(_entity, _type, _school_mask), do: 1.0

  def flat_amount(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    holders
    |> Enum.reduce(0, fn %Holder{auras: auras} = holder, acc ->
      stacks = holder_stacks(holder)

      Enum.reduce(auras, acc, fn
        %Aura{type: ^type, amount: amount}, inner when is_integer(amount) -> inner + amount * stacks
        _aura, inner -> inner
      end)
    end)
  end

  def flat_amount(_entity, _type), do: 0

  defp holder_stacks(%Holder{stacks: stacks}) when is_integer(stacks) and stacks > 1, do: stacks
  defp holder_stacks(_holder), do: 1

  def auras_of_type(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.filter(&match?(%Aura{type: ^type}, &1))
  end

  def auras_of_type(_entity, _type), do: []

  def rooted?(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.any?(holders, &Holder.has_aura_type?(&1, :mod_root))
  end

  def rooted?(_entity), do: false

  def has_aura?(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    Enum.any?(holders, &Holder.has_aura_type?(&1, type))
  end

  def has_aura?(_entity, _type), do: false

  def has_spell?(%{unit: %Unit{auras: holders}}, spell_id) when is_list(holders) and is_integer(spell_id) do
    Enum.any?(holders, &match?(%Holder{spell: %Spell{id: ^spell_id}}, &1))
  end

  def has_spell?(_entity, _spell_id), do: false

  def confuse_anchor_key(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    case Enum.find(holders, &(Holder.has_aura_type?(&1, :mod_confuse) or Holder.has_aura_type?(&1, :mod_fear))) do
      %Holder{applied_at: applied_at, spell: %Spell{id: spell_id}} -> {spell_id, applied_at}
      _ -> nil
    end
  end

  def confuse_anchor_key(_entity), do: nil
end
