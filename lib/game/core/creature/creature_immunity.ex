defmodule ThistleTea.Game.Core.Creature.CreatureImmunity do
  @moduledoc "Creature-template mechanic and school protection for spells, effects, damage, and school lockouts."

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect

  def mechanic?(%{internal: %{creature: %Creature{mechanic_immune_mask: mask}}}, mechanic)
      when is_integer(mask) and is_integer(mechanic) and mechanic in 1..31, do: (mask &&& 1 <<< (mechanic - 1)) != 0

  def mechanic?(_entity, _mechanic), do: false

  def school?(%{internal: %{creature: %Creature{school_immune_mask: mask}}}, school) when is_integer(mask),
    do: (mask &&& Spell.school_mask(school)) != 0

  def school?(_entity, _school), do: false

  def spell?(entity, %CastContext{} = context, %Spell{} = spell) do
    external_cast?(entity, context, spell) and not Spell.attribute?(spell, :no_immunities) and
      (mechanic?(entity, spell.mechanic) or (Spell.harmful?(spell) and school?(entity, spell.school)))
  end

  def effect?(entity, %CastContext{} = context, %Spell{} = spell, %Effect{} = effect) do
    external_cast?(entity, context, spell) and mechanic?(entity, effect.mechanic)
  end

  defp external_cast?(%{object: %{guid: guid}}, %CastContext{caster_guid: caster}, spell),
    do: guid != caster and not Spell.attribute?(spell, :ignore_caster_and_target_restrictions)
end
