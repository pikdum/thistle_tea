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
  alias ThistleTea.Game.Entity.Logic.Aura.DeathItem
  alias ThistleTea.Game.Entity.Logic.Aura.Lifecycle
  alias ThistleTea.Game.Entity.Logic.Aura.Periodic
  alias ThistleTea.Game.Entity.Logic.Aura.Reactions
  alias ThistleTea.Game.Entity.Logic.Aura.Transition
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Spell

  @frozen_aura_types [:mod_root, :mod_stun]
  @crowd_control_aura_types [:mod_charm, :mod_stun, :mod_confuse]

  defdelegate apply_spell(entity, context, spell, now), to: AuraApplication
  defdelegate apply_spell(entity, caster_guid, caster_level, spell, now), to: AuraApplication
  defdelegate transition(entity, change), to: Transition, as: :run
  defdelegate blocked_by_stronger_rank?(entity_or_holders, spell), to: AuraApplication
  defdelegate mechanic_immune?(entity, spell), to: AuraApplication
  defdelegate dispel_immune?(entity, spell), to: AuraApplication

  defdelegate interrupt_mask(action), to: Lifecycle
  defdelegate self_duration_events(entity, now), to: Lifecycle
  defdelegate expire_due(entity, now), to: Lifecycle
  defdelegate remove_with_interrupt_flags(entity, mask, now), to: Lifecycle
  defdelegate remove_with_interrupt_flags(entity, mask, now, preserved_types), to: Lifecycle
  defdelegate remove_spells(entity, spell_ids, now), to: Lifecycle
  defdelegate remove_stack(entity, spell_id, now), to: Lifecycle
  defdelegate remove_on_evade(entity, now), to: Lifecycle
  defdelegate spend_spell_charges(entity, spell_ids, now), to: Lifecycle
  defdelegate remove_aura_types(entity, aura_types, now), to: Lifecycle
  defdelegate remove_source_spell(entity, spell_id, caster_guid, now), to: Lifecycle
  defdelegate remove_area_aura(entity, area_guid, now), to: Lifecycle
  defdelegate delay_source_spell(entity, spell_id, caster_guid, delay_ms, now), to: Lifecycle
  defdelegate cancel_spell(entity, spell_id, now), to: Lifecycle
  defdelegate dispel(entity, dispel_type, now, polarity \\ nil, count \\ 1), to: Lifecycle
  defdelegate break_on_damage(entity, now), to: Lifecycle

  defdelegate enqueue_death_item_rewards(entity, old_health, new_health), to: DeathItem, as: :enqueue_rewards

  defdelegate tick(entity, now), to: Periodic
  defdelegate tick(entity, now, contexts), to: Periodic
  defdelegate next_event_at(entity), to: Periodic

  defdelegate reactions(entity, event, context), to: Reactions

  defdelegate absorb_damage(entity, damage, school, now), to: Absorption

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

  def misc_amounts(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    holders
    |> Enum.flat_map(fn %Holder{auras: auras} -> auras end)
    |> Enum.flat_map(fn
      %Aura{type: ^type, amount: amount, misc_value: misc} when is_integer(amount) and is_integer(misc) ->
        [{misc, amount}]

      _aura ->
        []
    end)
  end

  def misc_amounts(_entity, _type), do: []

  def attacker_spell_hit_chance(entity) do
    misc_amounts(entity, :mod_attacker_spell_hit_chance)
  end

  def versus_amount(pairs, mask) when is_list(pairs) and is_integer(mask) do
    Enum.reduce(pairs, 0, fn
      {misc, amount}, acc when Bitwise.band(misc, mask) != 0 -> acc + amount
      _pair, acc -> acc
    end)
  end

  def versus_amount(_pairs, _mask), do: 0

  def flat_amount(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    holders
    |> Enum.reduce(0, fn %Holder{auras: auras} = holder, acc ->
      stacks = holder_stacks(holder)

      Enum.reduce(auras, acc, fn
        %Aura{type: ^type, amount: amount}, inner when is_number(amount) -> inner + amount * stacks
        _aura, inner -> inner
      end)
    end)
  end

  def flat_amount(_entity, _type), do: 0

  def reflect_spell?(entity, spell, roll \\ fn -> :rand.uniform(100) end)

  def reflect_spell?(entity, %Spell{} = spell, roll) when is_function(roll, 0) do
    chance =
      flat_amount(entity, :reflect_spells) +
        flat_modifier(entity, :reflect_spells_school, Spell.school_mask(spell.school))

    chance > 0 and (chance >= 100 or roll.() <= chance)
  end

  def reflect_spell?(_entity, _spell, _roll), do: false

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

  def frozen?(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.any?(holders, fn
      %Holder{spell: %Spell{school: :frost}, auras: auras} ->
        Enum.any?(auras, &match?(%Aura{type: type} when type in @frozen_aura_types, &1))

      _holder ->
        false
    end)
  end

  def frozen?(_entity), do: false

  def has_aura?(%{unit: %Unit{auras: holders}}, type) when is_list(holders) do
    Enum.any?(holders, &Holder.has_aura_type?(&1, type))
  end

  def has_aura?(_entity, _type), do: false

  def has_spell?(%{unit: %Unit{auras: holders}}, spell_id) when is_list(holders) and is_integer(spell_id) do
    Enum.any?(holders, &match?(%Holder{spell: %Spell{id: ^spell_id}}, &1))
  end

  def has_spell?(_entity, _spell_id), do: false

  def spell_stacks(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    Enum.reduce(holders, %{}, fn %Holder{spell: %Spell{id: spell_id}} = holder, stacks ->
      Map.update(stacks, spell_id, holder_stacks(holder), &max(&1, holder_stacks(holder)))
    end)
  end

  def spell_stacks(_entity), do: %{}

  def effect_keys(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    for %Holder{spell: %Spell{id: spell_id}, auras: auras} <- holders,
        %Aura{index: index} <- auras,
        into: MapSet.new(),
        do: {spell_id, index}
  end

  def effect_keys(_entity), do: MapSet.new()

  def crowd_controlled?(%{unit: %Unit{auras: holders}} = entity) when is_list(holders) do
    frozen?(entity) or Fear.active?(entity) or
      Enum.any?(holders, &(Holder.charm?(&1) or Holder.has_any_type?(&1, @crowd_control_aura_types)))
  end

  def crowd_controlled?(_entity), do: false

  def source_spells(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    MapSet.new(holders, fn %Holder{spell: %Spell{} = spell, caster_guid: caster_guid} ->
      {spell.id, spell.spell_family, spell.family_flags_0, spell.family_flags_1, caster_guid}
    end)
  end

  def source_spells(_entity), do: MapSet.new()

  def dispel_options(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    holders
    |> Enum.flat_map(fn
      %Holder{spell: %Spell{dispel_type: type}, negative?: negative?} when is_integer(type) and type > 0 ->
        [{type, if(negative?, do: :negative, else: :positive)}]

      _holder ->
        []
    end)
    |> MapSet.new()
  end

  def dispel_options(_entity), do: MapSet.new()

  def school_immune?(%{unit: %Unit{auras: holders}}, school) when is_list(holders) do
    school_mask = Spell.school_mask(school)

    Enum.any?(holders, fn %Holder{auras: auras} ->
      Enum.any?(auras, fn
        %Aura{type: :school_immunity, misc_value: immune_mask} when is_integer(immune_mask) ->
          Bitwise.band(immune_mask, school_mask) != 0

        _aura ->
          false
      end)
    end)
  end

  def school_immune?(_entity, _school), do: false

  def confuse_anchor_key(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    case Enum.find(holders, &Holder.has_aura_type?(&1, :mod_confuse)) do
      %Holder{applied_at: applied_at, spell: %Spell{id: spell_id}} -> {spell_id, applied_at}
      _ -> nil
    end
  end

  def confuse_anchor_key(_entity), do: nil
end
