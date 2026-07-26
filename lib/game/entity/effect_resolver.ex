defmodule ThistleTea.Game.Entity.EffectResolver do
  @moduledoc """
  Resolves semantic gameplay requests into concrete boundary effects.
  """

  alias ThistleTea.Game.Entity.EffectResolver.Combat
  alias ThistleTea.Game.Entity.EffectResolver.Movement
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects

  @combat_requests [Effects.BladeFlurry, Effects.DropNearbyThreat, Effects.SecondaryMelee]
  @movement_requests [Effects.Charge, Effects.Leap, Effects.TeleportToSpellTarget]
  @spell_requests [Effects.DeliverSpell, Effects.DeliverSpellToQuery, Effects.HealThreat, Effects.TriggerSpell]

  def resolve(entity, effects) when is_list(effects) do
    Enum.flat_map(effects, &resolve(entity, &1))
  end

  def resolve(entity, %{__struct__: effect_module} = effect) when effect_module in @combat_requests do
    Combat.resolve(entity, effect)
  end

  def resolve(entity, %{__struct__: effect_module} = effect) when effect_module in @movement_requests do
    Movement.resolve(entity, effect)
  end

  def resolve(entity, %{__struct__: effect_module} = effect) when effect_module in @spell_requests do
    Spells.resolve(entity, effect)
  end

  def resolve(_entity, %{__struct__: _module} = effect), do: [effect]
end
