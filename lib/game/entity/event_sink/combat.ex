defmodule ThistleTea.Game.Entity.EventSink.Combat do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob.Incarnation
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CallForHelp
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  @victimstate_normal 1

  def emit(entity, %Effects.DeliverAttack{} = effect, _context) do
    Entity.receive_attack(effect.target_guid, effect.attack)
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
          spell_school_mask: Map.get(attack, :spell_school_mask, 0),
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
    Context.send_packet(context, Packet.build(<<>>, Opcodes.get(:SMSG_ATTACKSWING_NOTINRANGE)))

    entity
  end

  def emit(entity, %Effects.AttackOutcome{} = effect, _context) do
    Entity.attack_outcome(effect.target_guid, %{
      victim_guid: effect.source_guid,
      outcome: effect.outcome,
      damage: effect.damage,
      proc_damage: effect.proc_damage,
      spell_id: effect.spell_id
    })

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

  def emit(%Character{} = entity, %Effects.DropNearbyThreatResolved{} = effect, _context) do
    Metadata.update(entity.object.guid, effect.metadata)
    Enum.each(effect.target_guids, &Entity.drop_threat(&1, entity.object.guid))

    entity
  end

  def emit(entity, %Effects.DropNearbyThreatResolved{}, _context), do: entity

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
    Context.send_after(context, {:call_assistance, target_guid}, CallForHelp.assist_delay_ms())
    entity
  end

  def emit(entity, %Effects.CallAssistance{}, _context), do: entity

  def emit(%Mob{} = entity, %Effects.CallForHelp{target_guid: target_guid}, _context)
      when is_integer(target_guid) and target_guid > 0 do
    CallForHelp.pulse(entity, target_guid)
    entity
  end

  def emit(entity, %Effects.CallForHelp{}, _context), do: entity
end
