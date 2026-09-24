defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Drains typed effects, resolves semantic requests, and routes each concrete
  effect to its focused boundary interpreter.
  """

  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Combat
  alias ThistleTea.Game.Entity.EventSink.CombatLeashes
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.EventSink.CreatureGroups
  alias ThistleTea.Game.Entity.EventSink.Honor
  alias ThistleTea.Game.Entity.EventSink.InstanceData
  alias ThistleTea.Game.Entity.EventSink.Movement
  alias ThistleTea.Game.Entity.EventSink.ScriptedEvents
  alias ThistleTea.Game.Entity.EventSink.Spells
  alias ThistleTea.Game.Entity.EventSink.Summons
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.System.Battleground

  @client_effects [
    Effects.StartMirrorTimer,
    Effects.StopMirrorTimer,
    Effects.CancelAutoRepeat,
    Effects.FeignDeathResisted,
    Effects.ConsumeCastItem,
    Effects.TransformItem,
    Effects.ConsumeReagents,
    Effects.LaunchRanged,
    Effects.CreateItem,
    Effects.EmoteAnimation,
    Effects.EmoteState,
    Effects.TextEmote,
    Effects.EnchantItem,
    Effects.DisenchantItem,
    Effects.FactionAtWarChanged,
    Effects.FeedPet,
    Effects.ForcedReactionsChanged,
    Effects.ForwardScriptSteps,
    Effects.GameObjectCustomAnimation,
    Effects.GiveItem,
    Effects.MonsterTalk,
    Effects.OpenGameObject,
    Effects.OpenLock,
    Effects.PickPocket,
    Effects.SkinCorpse,
    Effects.RemoveInsignia,
    Effects.PlayObjectSound,
    Effects.PlaySound,
    Effects.QuestCastCredit,
    Effects.QuestEventCredit,
    Effects.QuestFail,
    Effects.QuestInteractionCredit,
    Effects.QuestKillCredit,
    Effects.ReputationChange,
    Effects.SendTaxiPath,
    Effects.ScriptSteps
  ]
  @combat_effects [
    Effects.EnterEvade,
    Effects.AdvanceCombatSkill,
    Effects.DurabilityLoss,
    Effects.AttackNotInRange,
    Effects.AttackBadFacing,
    Effects.AttackOutcome,
    Effects.AttackStart,
    Effects.AttackStop,
    Effects.AttackerGained,
    Effects.AttackerLost,
    Effects.AttackerStateUpdate,
    Effects.CallAssistance,
    Effects.CallForHelp,
    Effects.DeliverAttack,
    Effects.PvpContact,
    Effects.PvpFlagsChanged,
    Effects.DropNearbyThreatResolved,
    Effects.FeignDeathAppliedResolved,
    Effects.DropThreat,
    Effects.DuelDefeat,
    Effects.DuelInterrupted,
    Effects.DuelRequest,
    Effects.EnvironmentalDamage,
    Effects.StartAttack,
    Effects.TapClaimed,
    Effects.TapCleared,
    Effects.TemporaryThreat,
    Effects.ThreatRefGained,
    Effects.ThreatRefLost
  ]
  @movement_effects [
    Effects.BindHome,
    Effects.ChargeResolved,
    Effects.ClientControlChanged,
    Effects.CreatureTeleported,
    Effects.FeatherFallChanged,
    Effects.HoverChanged,
    Effects.Knockback,
    Effects.MonsterMove,
    Effects.MovementRootChanged,
    Effects.MovementSpeedChanged,
    Effects.MovementStopped,
    Effects.MovementInform,
    Effects.SetFacing,
    Effects.Teleport,
    Effects.TeleportToWorld,
    Effects.WaterWalkChanged
  ]
  @spell_effects [
    Effects.AddComboPoints,
    Effects.TeachSpell,
    Effects.CastRequirementsResolved,
    Effects.StartTriggeredChannel,
    Effects.ScriptedCast,
    Effects.CharmCast,
    Effects.PetSpellModifiers,
    Effects.SpellMagnetsChanged,
    Effects.SingleTargetAurasChanged,
    Effects.SingleTargetAurasLeft,
    Effects.SingleTargetCasterDied,
    Effects.AuraDuration,
    Effects.ChannelStart,
    Effects.ChannelUpdate,
    Effects.ClearCooldown,
    Effects.CooldownEvent,
    Effects.ActivateCooldown,
    Effects.DelayAura,
    Effects.DeliverHealThreat,
    Effects.DeliverSpell,
    Effects.SpellContact,
    Effects.DrainPower,
    Effects.GrantPower,
    Effects.HealEntity,
    Effects.PeriodicAuraLog,
    Effects.RemoveAura,
    Effects.ResurrectRequest,
    Effects.SpellCastFailed,
    Effects.SpellCastResult,
    Effects.SpellCooldown,
    Effects.SpellDamage,
    Effects.SpellDamageImmune,
    Effects.SpellDelayed,
    Effects.SpellDispel,
    Effects.SpellExtraAttacks,
    Effects.SpellInterrupted,
    Effects.SpellSchoolLockout,
    Effects.DispelFailed,
    Effects.SpellGo,
    Effects.SpellHeal,
    Effects.SpellLogMiss,
    Effects.SpellModifier,
    Effects.SpellStart,
    Effects.StandState,
    Effects.TriggerSpellRequest
  ]
  @summon_effects [
    Effects.ControlGranted,
    Effects.ControlReleased,
    Effects.DespawnAreaEffects,
    Effects.DespawnEntity,
    Effects.DespawnSelf,
    Effects.RemoveSelf,
    Effects.ActivateGameObject,
    Effects.ApplyGameObjectAction,
    Effects.RestoreGameObject,
    Effects.FinishGameObjectUse,
    Effects.RespawnGameObject,
    Effects.DespawnGameObject,
    Effects.LoadGameObjectSpawn,
    Effects.OperateGameObject,
    Effects.DismissPet,
    Effects.LearnPetSpell,
    Effects.LearnPetRecipe,
    Effects.PetHappinessChanged,
    Effects.PetProgressChanged,
    Effects.PetReactionChanged,
    Effects.PetDied,
    Effects.PetBroke,
    Effects.LeaveRitual,
    Effects.ReleaseControlled,
    Effects.RespawnSelf,
    Effects.SpawnAreaEffect,
    Effects.SpawnFarsight,
    Effects.SummonCreature,
    Effects.SummonGameObject,
    Effects.SummonPet,
    Effects.SummonMiniPet,
    Effects.SummonGuardians,
    Effects.SummonWild,
    Effects.SummonRequest,
    Effects.SummonTotem,
    Effects.TameCreature,
    Effects.ViewpointGranted,
    Effects.ViewpointReleased
  ]
  @scripted_event_effects [Effects.ScriptedEventCommand, Effects.SendScriptEvent]
  @instance_effects [Effects.InstanceCreatureEvent, Effects.InstanceDataCommand]

  def emit_pending(entity, context \\ nil) do
    {entity, effects} = Effects.drain(entity)
    emit(entity, effects, context)
  end

  def emit(entity, effects, context \\ nil)

  def emit(entity, effects, context) when is_list(effects) do
    context = context || Context.from_entity(entity)

    entity
    |> EffectResolver.resolve(effects)
    |> Enum.reduce(entity, &emit_resolved(&2, &1, context))
  end

  def emit(entity, %{__struct__: _module} = effect, context) do
    emit(entity, [effect], context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @client_effects do
    ClientProjection.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %Effects.BattlegroundDeath{world: world, defeat: defeat}, _context) do
    Battleground.player_died(world, defeat)
    entity
  end

  defp emit_resolved(entity, %Effects.CancelBattlegroundResurrection{world: world, guid: guid}, _context) do
    Battleground.cancel_resurrection(world, guid)
    entity
  end

  defp emit_resolved(entity, %{__struct__: type} = effect, context)
       when type in [Effects.CreatureGroupEvent, Effects.CreatureGroupCommand] do
    CreatureGroups.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %Effects.CombatLeashEvent{} = effect, context) do
    CombatLeashes.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: type} = effect, context)
       when type in [Effects.HonorContribution, Effects.HonorAward] do
    Honor.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @combat_effects do
    Combat.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @movement_effects do
    Movement.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @spell_effects do
    Spells.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @summon_effects do
    Summons.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context)
       when effect_module in @scripted_event_effects do
    ScriptedEvents.emit(entity, effect, context)
  end

  defp emit_resolved(entity, %{__struct__: effect_module} = effect, context) when effect_module in @instance_effects do
    InstanceData.emit(entity, effect, context)
  end

  def deliver_spell(%Effects.DeliverSpell{} = effect) do
    Spells.deliver_spell(effect)
  end
end
