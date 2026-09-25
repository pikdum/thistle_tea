defmodule ThistleTea.Game.Entity.EffectResolver do
  @moduledoc """
  Resolves semantic gameplay requests into concrete boundary effects.
  """

  alias ThistleTea.Game.Entity.EffectResolver.Battleground
  alias ThistleTea.Game.Entity.EffectResolver.Combat
  alias ThistleTea.Game.Entity.EffectResolver.Durability
  alias ThistleTea.Game.Entity.EffectResolver.Honor
  alias ThistleTea.Game.Entity.EffectResolver.Movement
  alias ThistleTea.Game.Entity.EffectResolver.PetLearning
  alias ThistleTea.Game.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Emote
  alias ThistleTea.Game.World.Loader.Emote, as: EmoteLoader

  @combat_requests [Effects.BladeFlurry, Effects.DropNearbyThreat, Effects.FeignDeathApplied, Effects.SecondaryMelee]
  @movement_requests [
    Effects.Charge,
    Effects.Leap,
    Effects.TeleportHome,
    Effects.TeleportNearCaster,
    Effects.TeleportToSpellTarget
  ]
  @spell_requests [
    Effects.CheckCastRequirements,
    Effects.SpellGameObjectAction,
    Effects.DeliverSpell,
    Effects.ProcDamage,
    Effects.DeliverSpellToQuery,
    Effects.HealThreat,
    Effects.TriggerSpell,
    Effects.SpellDamage,
    Effects.SpellHeal
  ]

  def resolve(entity, effects) when is_list(effects) do
    Enum.flat_map(effects, &resolve(entity, &1))
  end

  def resolve(entity, %Effects.DurabilityDamage{} = effect), do: Durability.resolve(entity, effect)

  def resolve(_entity, %Effects.Emote{emote_id: id}) do
    case EmoteLoader.animation(id) do
      nil -> []
      definition -> [Emote.animation_effect(definition)]
    end
  end

  def resolve(entity, %Effects.PlayerDefeated{} = effect), do: Battleground.resolve(entity, effect)
  def resolve(entity, %Effects.CreatureDefeated{} = effect), do: Battleground.resolve(entity, effect)
  def resolve(_entity, %Effects.HonorDamage{} = effect), do: Honor.resolve(effect)
  def resolve(entity, %Effects.HonorCreatureKill{} = effect), do: Honor.creature_kill(entity, effect)
  def resolve(entity, %Effects.PetAbilityUsed{} = effect), do: PetLearning.resolve(entity, effect)

  def resolve(entity, %Effects.DeliverAttack{} = effect) do
    Pvp.contacts(entity, entity.object.guid, effect.target_guid, :attack) ++ [effect]
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
