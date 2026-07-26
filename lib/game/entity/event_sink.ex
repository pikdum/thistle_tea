defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Drains typed effects, resolves semantic requests, and routes each concrete
  effect to its focused boundary interpreter.
  """

  alias ThistleTea.Game.Entity.EffectResolver
  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Combat
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.EventSink.Movement
  alias ThistleTea.Game.Entity.EventSink.Spells
  alias ThistleTea.Game.Entity.EventSink.Summons
  alias ThistleTea.Game.Entity.Logic.Effects

  @client_effects [
    Effects.ConsumeCastItem,
    Effects.ConsumeReagents,
    Effects.CreateItem,
    Effects.Emote,
    Effects.EnchantItem,
    Effects.FeedPet,
    Effects.ForwardScriptSteps,
    Effects.GiveItem,
    Effects.MonsterTalk,
    Effects.OpenGameObject,
    Effects.PlayObjectSound,
    Effects.PlaySound,
    Effects.ScriptSteps
  ]
  @combat_effects [
    Effects.AttackNotInRange,
    Effects.AttackOutcome,
    Effects.AttackStart,
    Effects.AttackStop,
    Effects.AttackerGained,
    Effects.AttackerLost,
    Effects.AttackerStateUpdate,
    Effects.CallAssistance,
    Effects.CallForHelp,
    Effects.DeliverAttack,
    Effects.DropNearbyThreatResolved,
    Effects.DropThreat,
    Effects.DuelDefeat,
    Effects.DuelInterrupted,
    Effects.DuelRequest,
    Effects.StartAttack,
    Effects.TapClaimed,
    Effects.TapCleared,
    Effects.ThreatRefGained,
    Effects.ThreatRefLost
  ]
  @movement_effects [
    Effects.ChargeResolved,
    Effects.FeatherFallChanged,
    Effects.HoverChanged,
    Effects.MonsterMove,
    Effects.MovementRootChanged,
    Effects.MovementSpeedChanged,
    Effects.MovementStopped,
    Effects.SetFacing,
    Effects.Teleport,
    Effects.TeleportToWorld,
    Effects.WaterWalkChanged
  ]
  @spell_effects [
    Effects.AuraDuration,
    Effects.ChannelStart,
    Effects.ChannelUpdate,
    Effects.ClearCooldown,
    Effects.CooldownEvent,
    Effects.DelayAura,
    Effects.DeliverHealThreat,
    Effects.DeliverSpell,
    Effects.DeliverSpellOutcome,
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
    Effects.SpellDelayed,
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
    Effects.DismissPet,
    Effects.LeaveRitual,
    Effects.ReleaseControlled,
    Effects.SpawnAreaEffect,
    Effects.SpawnFarsight,
    Effects.SummonCreature,
    Effects.SummonGameObject,
    Effects.SummonPet,
    Effects.SummonRequest,
    Effects.SummonTotem,
    Effects.TameCreature,
    Effects.ViewpointGranted,
    Effects.ViewpointReleased
  ]

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

  def deliver_spell(%Effects.DeliverSpell{} = effect) do
    Spells.deliver_spell(effect)
  end
end
