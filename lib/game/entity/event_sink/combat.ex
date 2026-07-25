defmodule ThistleTea.Game.Entity.EventSink.Combat do
  @moduledoc false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.StealthDetection
  alias ThistleTea.Game.Entity.Server.Mob.Incarnation
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Scripts
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CallForHelp
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  @victimstate_normal 1

  def emit(entity, %Effects.DeliverAttack{} = effect) do
    Entity.receive_attack(effect.target_guid, effect.attack)
    entity
  end

  def emit(entity, %Effects.AttackStart{source_guid: source_guid, target_guid: target_guid})
      when is_integer(source_guid) and is_integer(target_guid) do
    %Message.SmsgAttackstart{
      attacker: source_guid,
      victim: target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.AttackStop{} = effect) do
    %Message.SmsgAttackstop{
      player: effect.source_guid,
      enemy: effect.target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Effects.DuelDefeat{source_guid: winner_guid, target_guid: loser_guid}) do
    DuelSystem.defeat(loser_guid, winner_guid)
    entity
  end

  def emit(entity, %Effects.DuelInterrupted{target_guid: guid}) do
    DuelSystem.interrupt(guid)
    entity
  end

  def emit(entity, %Effects.DuelRequest{position: {world, x, y, z}} = effect) do
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

  def emit(entity, %Effects.AttackerStateUpdate{} = effect) do
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

  def emit(entity, %Effects.AttackNotInRange{}) do
    Packet.build(<<>>, Opcodes.get(:SMSG_ATTACKSWING_NOTINRANGE))
    |> Network.send_packet()

    entity
  end

  def emit(entity, %Effects.AttackOutcome{} = effect) do
    Entity.attack_outcome(effect.target_guid, %{
      victim_guid: effect.source_guid,
      outcome: effect.outcome,
      damage: effect.damage,
      proc_damage: effect.proc_damage,
      spell_id: effect.spell_id
    })

    entity
  end

  def emit(entity, %Effects.AttackerGained{target_guid: target_guid}) do
    Metadata.increment(target_guid, :attacker_count)
    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Effects.ThreatRefGained{target_guid: target_guid}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_gained(target_guid, mob_guid, Incarnation.id(entity))
    end

    entity
  end

  def emit(%{object: %{guid: mob_guid}} = entity, %Effects.ThreatRefLost{target_guid: target_guid}) do
    if Guid.entity_type(target_guid) == :player do
      Entity.threat_ref_lost(target_guid, mob_guid, Incarnation.id(entity))
    end

    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Effects.DropThreat{target_guid: mob_guid}) do
    Entity.drop_threat(mob_guid, guid)
    entity
  end

  def emit(entity, %Effects.DropThreat{}), do: entity

  def emit(%Character{} = entity, %Effects.DropNearbyThreat{}) do
    Metadata.update(entity.object.guid, StealthDetection.target_metadata(entity))

    entity
    |> World.nearby_mobs(250)
    |> Enum.each(fn {mob_guid, _distance} -> Entity.drop_threat(mob_guid, entity.object.guid) end)

    entity
  end

  def emit(entity, %Effects.DropNearbyThreat{}), do: entity

  def emit(%Character{} = entity, %Effects.BladeFlurry{target_guid: primary, damage: damage} = effect)
      when is_integer(effect.spell_id) do
    deliver_secondary_melee(entity, primary, damage, effect.spell_id, Scripts.blade_flurry_radius_yards())

    entity
  end

  def emit(entity, %Effects.BladeFlurry{}), do: entity

  def emit(%Character{} = entity, %Effects.SecondaryMelee{} = effect) do
    deliver_secondary_melee(entity, effect.target_guid, effect.damage, effect.spell_id, effect.range_yards)
    entity
  end

  def emit(entity, %Effects.SecondaryMelee{}), do: entity

  def emit(entity, %Effects.AttackerLost{target_guid: target_guid}) do
    Metadata.decrement(target_guid, :attacker_count, 0)
    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Effects.TapCleared{}) do
    Metadata.update(guid, %{tapped_player: nil, tapped_group_id: nil})
    entity
  end

  def emit(entity, %Effects.StartAttack{target_guid: target_guid}) when is_integer(target_guid) and target_guid > 0 do
    send(self(), {:force_attack, target_guid})
    entity
  end

  def emit(entity, %Effects.StartAttack{}), do: entity

  def emit(%Mob{} = entity, %Effects.CallAssistance{target_guid: target_guid})
      when is_integer(target_guid) and target_guid > 0 do
    Process.send_after(self(), {:call_assistance, target_guid}, CallForHelp.assist_delay_ms())
    entity
  end

  def emit(entity, %Effects.CallAssistance{}), do: entity

  def emit(%Mob{} = entity, %Effects.CallForHelp{target_guid: target_guid})
      when is_integer(target_guid) and target_guid > 0 do
    CallForHelp.pulse(entity, target_guid)
    entity
  end

  def emit(entity, %Effects.CallForHelp{}), do: entity

  defp deliver_secondary_melee(entity, primary, damage, spell_id, radius) do
    secondary =
      entity
      |> SpellTargetResolver.resolve_query({:caster_aoe, radius})
      |> Enum.reject(&(&1 == primary))
      |> random_target()

    with secondary when is_integer(secondary) <- secondary,
         %Spell{} = spell <- SpellLoader.load(spell_id),
         %Spell.Effect{} = effect <- List.first(Spell.damage_effects(spell)) do
      spell = %{spell | effects: [%{effect | base_points: damage, die_sides: 0, base_dice: 0}]}
      context = CastContext.from_caster(entity, spell, secondary)
      Entity.receive_spell(secondary, context, spell)
    else
      _ -> nil
    end
  end

  defp random_target([]), do: nil
  defp random_target(targets), do: Enum.random(targets)
end
