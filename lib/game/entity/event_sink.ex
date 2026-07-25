defmodule ThistleTea.Game.Entity.EventSink do
  @moduledoc """
  Drains typed effects from an entity and routes each one to its focused
  boundary interpreter.
  """

  alias ThistleTea.Game.Entity.EventSink.ClientProjection
  alias ThistleTea.Game.Entity.EventSink.Combat
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
    Effects.ObjectUpdate,
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
    Effects.BladeFlurry,
    Effects.CallAssistance,
    Effects.CallForHelp,
    Effects.DeliverAttack,
    Effects.DropNearbyThreat,
    Effects.DropThreat,
    Effects.DuelDefeat,
    Effects.DuelInterrupted,
    Effects.DuelRequest,
    Effects.SecondaryMelee,
    Effects.StartAttack,
    Effects.TapCleared,
    Effects.ThreatRefGained,
    Effects.ThreatRefLost
  ]
  @movement_effects [
    Effects.Charge,
    Effects.FeatherFallChanged,
    Effects.HoverChanged,
    Effects.Leap,
    Effects.MonsterMove,
    Effects.MovementRootChanged,
    Effects.MovementSpeedChanged,
    Effects.MovementStopped,
    Effects.SetFacing,
    Effects.Teleport,
    Effects.TeleportToSpellTarget,
    Effects.WaterWalkChanged
  ]
  @spell_effects [
    Effects.AuraDuration,
    Effects.ChannelStart,
    Effects.ChannelUpdate,
    Effects.ClearCooldown,
    Effects.CooldownEvent,
    Effects.DelayAura,
    Effects.DeliverSpell,
    Effects.DeliverSpellOutcome,
    Effects.DrainPower,
    Effects.GrantPower,
    Effects.HealEntity,
    Effects.HealThreat,
    Effects.PeriodicAuraLog,
    Effects.RedirectDamage,
    Effects.RefreshPartyAura,
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
    Effects.TriggerSpell
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

  def emit_pending(entity) do
    {entity, effects} = Effects.drain(entity)
    emit(entity, effects)
  end

  def emit(entity, effects) when is_list(effects) do
    Enum.reduce(effects, entity, &emit(&2, &1))
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @client_effects do
    ClientProjection.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @combat_effects do
    Combat.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @movement_effects do
    Movement.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @spell_effects do
    Spells.emit(entity, effect)
  end

  def emit(entity, %{__struct__: effect_module} = effect) when effect_module in @summon_effects do
    Summons.emit(entity, effect)
  end

  def deliver_spell(%Effects.DeliverSpell{} = effect) do
    Spells.deliver_spell(effect)
  end
end
