defmodule ThistleTea.Game.World.Entity.EffectResolver do
  @moduledoc """
  Resolves semantic gameplay requests into concrete boundary effects.
  """

  alias ThistleTea.Game.Core.Chat.Emote
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Effects.WhenGrouped
  alias ThistleTea.Game.World.Entity.EffectResolver.Battleground
  alias ThistleTea.Game.World.Entity.EffectResolver.Combat
  alias ThistleTea.Game.World.Entity.EffectResolver.DeathItem
  alias ThistleTea.Game.World.Entity.EffectResolver.Durability
  alias ThistleTea.Game.World.Entity.EffectResolver.Honor
  alias ThistleTea.Game.World.Entity.EffectResolver.LocalDefense
  alias ThistleTea.Game.World.Entity.EffectResolver.Movement
  alias ThistleTea.Game.World.Entity.EffectResolver.PetLearning
  alias ThistleTea.Game.World.Entity.EffectResolver.Pvp
  alias ThistleTea.Game.World.Entity.EffectResolver.SpellLaunch
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Emote, as: EmoteLoader
  alias ThistleTea.Game.World.System.Party, as: PartySystem

  @combat_requests [
    Effects.BladeFlurry,
    Effects.DropNearbyThreat,
    Effects.FeignDeathApplied,
    Effects.PetSpellAttack,
    Effects.SecondaryMelee
  ]
  @movement_requests [
    Effects.Charge,
    Effects.Leap,
    Effects.TeleportHome,
    Effects.TeleportNearCaster,
    Effects.TeleportToSpellTarget
  ]
  @spell_requests [
    Effects.SummonMount,
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

  def resolve(entity, %RandomChoice{} = choice) do
    case RandomChoice.total_weight(choice) do
      0 -> []
      total -> resolve(entity, RandomChoice.select(choice, :rand.uniform(total)))
    end
  end

  def resolve(entity, %WhenGrouped{guids: [first, second], effects: effects}) do
    case PartySystem.group_of(first) do
      %{members: members} -> if Enum.any?(members, &(&1.guid == second)), do: resolve(entity, effects), else: []
      _ungrouped -> []
    end
  end

  def resolve(_entity, %Effects.DeathItemReward{} = effect), do: DeathItem.resolve(effect)

  def resolve(entity, %Effects.SpellLaunched{} = effect), do: SpellLaunch.resolve(entity, effect)

  def resolve(entity, %Effects.DurabilityDamage{} = effect), do: Durability.resolve(entity, effect)

  def resolve(_entity, %Effects.Emote{emote_id: id}) do
    case EmoteLoader.animation(id) do
      nil -> []
      definition -> [Emote.animation_effect(definition)]
    end
  end

  def resolve(entity, %Effects.PlayerDefeated{} = effect), do: Battleground.resolve(entity, effect)

  def resolve(entity, %Effects.CreatureDefeated{} = effect),
    do: Battleground.resolve(entity, effect) ++ LocalDefense.resolve(entity, effect)

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
