defmodule ThistleTea.Game.Core.Aura.EffectImmunity do
  @moduledoc """
  Mechanic, aura-state, dispel-type, and spell-effect immunity from active holders and creature defaults.
  Immunity filters individual effects and optionally purges matching holders.
  """

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Aura.Invulnerability
  alias ThistleTea.Game.Core.Creature.CreatureFlags
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Immunity

  @harmful_auras [
    :mod_stun,
    :mod_root,
    :mod_fear,
    :mod_confuse,
    :mod_charm,
    :mod_possess,
    :mod_silence,
    :mod_taunt,
    :mod_pacify,
    :mod_pacify_silence,
    :mod_decrease_speed,
    :periodic_damage,
    :periodic_damage_percent,
    :periodic_leech,
    :periodic_mana_leech
  ]

  def blocked?(%{unit: %Unit{auras: holders}} = entity, %Spell{} = spell, %Effect{} = effect) when is_list(holders) do
    not Spell.attribute?(spell, :ignore_caster_and_target_restrictions) and
      (Invulnerability.blocks_protection?(entity, spell) or sessile_immunity?(entity, effect) or
         Enum.any?(holders, &blocks?(&1, spell, effect)))
  end

  def blocked?(_entity, _spell, _effect), do: false

  def mechanic?(%Holder{} = holder, %Spell{mechanic: mechanic} = spell) when is_integer(mechanic) and mechanic > 0 do
    not Spell.attribute?(spell, :no_immunities) and
      not Spell.attribute?(spell, :ignore_caster_and_target_restrictions) and
      applies_to_polarity?(holder, Enum.any?(spell.effects, &harmful_effect?(spell, &1))) and
      Enum.any?(holder.auras, &match?(%Aura{type: :mechanic_immunity, misc_value: ^mechanic}, &1))
  end

  def mechanic?(_holder, _spell), do: false

  def friendly_mechanics(%{unit: %Unit{auras: holders}}) when is_list(holders) do
    for holder <- holders,
        applies_to_polarity?(holder, false),
        %Aura{type: :mechanic_immunity, misc_value: mechanic} <- holder.auras,
        is_integer(mechanic) and mechanic > 0,
        into: MapSet.new(),
        do: mechanic
  end

  def friendly_mechanics(_entity), do: MapSet.new()

  def blocks_friendly_mechanic?(%MapSet{} = mechanics, %Spell{} = spell) do
    not Spell.harmful?(spell) and
      not Spell.attribute?(spell, :no_immunities) and
      not Spell.attribute?(spell, :ignore_caster_and_target_restrictions) and
      MapSet.member?(mechanics, spell.mechanic)
  end

  def blocks_friendly_mechanic?(_mechanics, _spell), do: false

  def purge_new(previous, desired) do
    applications = MapSet.new(previous, &application_key/1)

    Enum.reduce(desired, desired, fn holder, current ->
      if MapSet.member?(applications, application_key(holder)) or holder not in current,
        do: current,
        else: purge(current, holder)
    end)
  end

  defp application_key(%Holder{} = holder) do
    {Holder.key(holder), holder.applied_at, Enum.map(holder.auras, &{&1.index, &1.type, &1.misc_value})}
  end

  defp sessile_immunity?(entity, %Effect{type: type, aura: aura}) do
    CreatureFlags.has?(entity, :sessile) and
      (type in [:distract, :pull, :knockback] or aura in [:mod_confuse, :mod_fear, :mod_root])
  end

  def purge(holders, %Holder{} = incoming) do
    immunity = Immunity.purging(incoming)

    Enum.reject(holders, fn holder ->
      holder.spell.id != incoming.spell.id and
        (Enum.any?(holder.auras, &Immunity.state?(immunity, &1.type)) or
           Immunity.dispel?(immunity, holder.spell) or purge_mechanic?(holder, immunity) or
           purge_school?(holder, incoming, immunity))
    end)
  end

  defp purge_mechanic?(%Holder{spell: spell, auras: auras}, immunity) do
    active = MapSet.new(auras, & &1.index)

    not Spell.attribute?(spell, :no_immunities) and
      (Immunity.mechanic?(immunity, spell.mechanic) or
         Enum.any?(spell.effects, &(Immunity.mechanic?(immunity, &1.mechanic) and MapSet.member?(active, &1.index))))
  end

  defp purge_school?(%Holder{spell: spell, negative?: true}, %Holder{negative?: false}, immunity),
    do: not Spell.attribute?(spell, :no_immunities) and Immunity.school?(immunity, spell)

  defp purge_school?(_holder, _incoming, _immunity), do: false

  defp blocks?(%Holder{} = holder, spell, effect) do
    applies_to_polarity?(holder, harmful_effect?(spell, effect)) and Enum.any?(holder.auras, &matches?(&1, effect))
  end

  defp applies_to_polarity?(%Holder{spell: immunity, negative?: negative?}, harmful?) do
    Spell.attribute?(immunity, :immunity_to_hostile_and_friendly_effects) or
      negative? != harmful?
  end

  defp harmful_effect?(spell, effect) do
    Spell.attribute?(spell, :negative) or Spell.charm_effect?(spell, effect) or effect.aura in @harmful_auras or
      Spell.harmful?(%{spell | effects: [effect]})
  end

  defp matches?(%Aura{type: :effect_immunity, misc_value: type}, %Effect{type: type}), do: true

  defp matches?(%Aura{type: :state_immunity, misc_value: type}, %Effect{aura: type}) when not is_nil(type), do: true

  defp matches?(%Aura{type: :mechanic_immunity, misc_value: mechanic}, %Effect{mechanic: mechanic})
       when is_integer(mechanic) and mechanic > 0, do: true

  defp matches?(_aura, _effect), do: false
end
