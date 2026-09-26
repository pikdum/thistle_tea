defmodule ThistleTea.Game.Entity.EventSink.Combat do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AttackSchool
  alias ThistleTea.Game.Entity.Logic.CombatLeash
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.FeignDeath
  alias ThistleTea.Game.Entity.Logic.Pvp
  alias ThistleTea.Game.Entity.Server.Mob.Incarnation
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CallForHelp
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  @victimstate_normal 1

  def emit(%Mob{object: %{guid: guid}} = entity, %Effects.EnterEvade{target_guid: guid}, context) do
    Context.cast(context, :enter_evade)
    entity
  end

  def emit(entity, %Effects.EnterEvade{target_guid: guid}, _context) do
    Entity.enter_evade(guid)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.PvpContact{target_guid: guid} = effect, _context) do
    Pvp.contact(entity, effect.role, effect.other, effect.now, effect.combat?)
  end

  def emit(entity, %Effects.PvpContact{} = effect, _context) do
    Entity.pvp_contact(effect.target_guid, effect)
    entity
  end

  def emit(%Character{} = entity, %Effects.PvpFlagsChanged{enabled?: enabled}, _context) do
    guids = [Companion.creature_guid(entity) | Map.values(entity.internal.totem_guids)]

    guids
    |> Enum.filter(&is_integer/1)
    |> Enum.uniq()
    |> Enum.each(&Entity.sync_pvp(&1, entity.object.guid, enabled))

    entity
  end

  def emit(entity, %Effects.PvpFlagsChanged{}, _context), do: entity

  def emit(entity, %Effects.DurabilityLoss{} = effect, context) do
    if effect.target_guid == entity.object.guid do
      Context.send(context, effect)
    else
      case Entity.pid(effect.target_guid) do
        pid when is_pid(pid) -> send(pid, effect)
        _missing -> :ok
      end
    end

    entity
  end

  def emit(entity, %Effects.EnvironmentalDamage{} = effect, _context) do
    damage_type = %{exhaustion: 0, drowning: 1, fall: 2, lava: 3, slime: 4, fire: 5} |> Map.fetch!(effect.type)

    %Message.SmsgEnvironmentalDamageLog{
      guid: entity.object.guid,
      damage_type: damage_type,
      damage: effect.damage,
      absorb: effect.absorbed,
      resist: effect.resisted
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.DeliverAttack{} = effect, _context) do
    Entity.receive_attack(effect.target_guid, effect.attack)
    entity
  end

  def emit(entity, %Effects.SharedDamage{} = effect, context) do
    if effect.target_guid == entity.object.guid,
      do: Context.cast(context, {:receive_shared_damage, effect}),
      else: Entity.receive_shared_damage(effect.target_guid, effect)

    entity
  end

  def emit(entity, %Effects.AttackStart{source_guid: source_guid, target_guid: target_guid}, _context)
      when is_integer(source_guid) and is_integer(target_guid) do
    %Message.SmsgAttackstart{
      attacker: source_guid,
      victim: target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.AttackStop{} = effect, _context) do
    %Message.SmsgAttackstop{
      player: effect.source_guid,
      enemy: effect.target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.DuelDefeat{source_guid: winner_guid, target_guid: loser_guid}, _context) do
    DuelSystem.defeat(loser_guid, winner_guid)
    entity
  end

  def emit(entity, %Effects.DuelInterrupted{target_guid: guid}, _context) do
    DuelSystem.interrupt(guid)
    entity
  end

  def emit(entity, %Effects.DuelRequest{position: {world, x, y, z}} = effect, _context) do
    DuelSystem.challenge(%{
      initiator_guid: effect.source_guid,
      initiator_level: effect.source_level,
      opponent_guid: effect.target_guid,
      entry: effect.entry,
      world: world,
      flag_position: {x, y, z},
      orientation: effect.facing
    })

    entity
  end

  def emit(entity, %Effects.AttackerStateUpdate{} = effect, _context) do
    attack = effect.attack || %{}
    damage = effect.damage || 0

    %Message.SmsgAttackerstateupdate{
      attacker: effect.source_guid,
      target: effect.target_guid,
      hit_info: Map.get(attack, :hit_info, 0x2),
      total_damage: damage,
      damages: [
        %{
          school: attack |> Map.get(:spell_school_mask) |> AttackSchool.from_mask() |> Spell.school_index(),
          damage_float: damage * 1.0,
          damage_uint: damage,
          absorb: Map.get(attack, :absorb, 0),
          resist: Map.get(attack, :resist, 0)
        }
      ],
      damage_state: Map.get(attack, :damage_state, @victimstate_normal),
      unknown1: Map.get(attack, :unknown1, 0),
      spell_id: Map.get(attack, :spell_id, 0),
      blocked_amount: Map.get(attack, :blocked_amount, 0)
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.AttackNotInRange{}, context) do
    Context.send_packet(context, %Message.SmsgAttackswingNotinrange{})

    entity
  end

  def emit(entity, %Effects.AttackBadFacing{}, context) do
    Context.send_packet(context, %Message.SmsgAttackswingBadfacing{})

    entity
  end

  def emit(entity, %Effects.AdvanceCombatSkill{} = effect, _context) do
    Entity.advance_combat_skill(effect.target_guid, effect.skill_id)
    entity
  end

  def emit(entity, %Effects.AttackOutcome{} = effect, _context) do
    Entity.attack_outcome(effect.target_guid, %{
      victim_guid: effect.source_guid,
      outcome: effect.outcome,
      proc_ex: effect.proc_ex,
      proc_origin: effect.proc_origin,
      damage: effect.damage,
      proc_damage: effect.proc_damage,
      spell_id: effect.spell_id,
      spell: effect.spell,
      hand: effect.hand,
      extra_attack?: effect.extra_attack?
    })

    entity
  end

  def emit(entity, %Effects.KillOutcome{} = effect, _context) do
    Entity.kill_outcome(effect.target_guid, effect.victim)
    entity
  end

  def emit(entity, %Effects.AttackerGained{target_guid: target_guid}, _context) do
    Metadata.increment(target_guid, :attacker_count)
    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Effects.ThreatRefGained{target_guid: target_guid}, _context) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_gained(target_guid, mob_guid, Incarnation.id(entity))
    end

    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Effects.ThreatRefLost{target_guid: target_guid}, _context) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_lost(target_guid, mob_guid, Incarnation.id(entity))
    end

    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.DropThreat{target_guid: mob_guid}, _context) do
    Entity.drop_threat(mob_guid, guid)
    entity
  end

  def emit(entity, %Effects.DropThreat{}, _context), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.TemporaryThreat{} = effect, _context) do
    Entity.temporary_threat(effect.target_guid, guid, effect.incarnation_id, effect.amount)
    entity
  end

  def emit(entity, %Effects.TemporaryThreat{}, _context), do: entity

  def emit(%Character{} = entity, %Effects.DropNearbyThreatResolved{} = effect, _context) do
    Presence.sync(entity, effect.metadata)
    Enum.each(effect.target_guids, &Entity.drop_threat(&1, entity.object.guid))

    entity
  end

  def emit(entity, %Effects.DropNearbyThreatResolved{}, _context), do: entity

  def emit(entity, %Effects.FeignDeathAppliedResolved{} = effect, _context) do
    case entity do
      %Character{} -> Presence.sync(entity, %{})
      %Mob{} -> Metadata.update(entity.object.guid, %{feigning_death?: FeignDeath.successful?(entity)})
    end

    Enum.each(effect.target_guids, &Entity.feign_death_target_lost(&1, entity.object.guid))
    entity
  end

  def emit(entity, %Effects.AttackerLost{target_guid: target_guid}, _context) do
    Metadata.decrement(target_guid, :attacker_count, 0)
    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.TapCleared{}, _context) do
    Metadata.update(guid, %{tapped_player: nil, tapped_group_id: nil})
    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.TapClaimed{} = effect, _context) do
    Metadata.update(guid, %{tapped_player: effect.player_guid, tapped_group_id: effect.group_id})
    entity
  end

  def emit(entity, %Effects.StartAttack{target_guid: target_guid}, context)
      when is_integer(target_guid) and target_guid > 0 do
    Context.send(context, {:force_attack, target_guid})
    entity
  end

  def emit(entity, %Effects.StartAttack{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.CallAssistance{target_guid: target_guid}, context)
      when is_integer(target_guid) and target_guid > 0 do
    helpers = CallForHelp.capture(entity, target_guid)

    if helpers != [] do
      message = {:call_assistance, target_guid, helpers, CombatLeash.reference(entity)}
      Context.send_after(context, message, CallForHelp.assist_delay_ms())
    end

    entity
  end

  def emit(entity, %Effects.CallAssistance{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.CallForHelp{target_guid: target_guid, radius: radius}, _context)
      when is_integer(target_guid) and target_guid > 0 do
    if is_number(radius) and radius > 0 do
      CallForHelp.pulse(entity, target_guid, radius)
    else
      CallForHelp.pulse(entity, target_guid)
    end

    entity
  end

  def emit(entity, %Effects.CallForHelp{}, _context), do: entity
end
