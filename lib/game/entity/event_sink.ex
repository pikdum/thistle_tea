defmodule ThistleTea.Game.Entity.EventSink do
  alias ThistleTea.Character
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Event
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Opcodes
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  def emit_pending(entity) do
    {entity, events} = Event.drain(entity)
    emit(entity, events)
  end

  def emit(entity, events) when is_list(events) do
    Enum.reduce(events, entity, &emit(&2, &1))
  end

  def emit(entity, %Event{type: :spell_damage} = event) do
    %Message.SmsgSpellNonMeleeDamageLog{
      attacker: event.source_guid || 0,
      target: event.target_guid,
      spell_id: event.spell_id,
      damage: event.damage,
      school: school_index(event.school),
      periodic?: event.periodic?
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :aura_duration} = event) do
    Network.send_packet(%Message.SmsgUpdateAuraDuration{
      aura_slot: event.aura_slot,
      duration_ms: event.duration_ms
    })

    entity
  end

  def emit(%Mob{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)

    Message.SmsgMonsterMove.build_stop(entity)
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(%Character{} = entity, %Event{type: :movement_stopped}) do
    World.update_position(entity)
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_root_changed, rooted?: true}) do
    Network.send_packet(%Message.SmsgForceMoveRoot{guid: guid})
    entity
  end

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_root_changed, rooted?: false}) do
    Network.send_packet(%Message.SmsgForceMoveUnroot{guid: guid})
    entity
  end

  def emit(entity, %Event{type: :movement_root_changed}), do: entity

  def emit(%Character{object: %{guid: guid}} = entity, %Event{type: :movement_speed_changed, speed: speed})
      when is_number(speed) do
    Network.send_packet(%Message.SmsgForceRunSpeedChange{guid: guid, speed: speed})
    entity
  end

  def emit(entity, %Event{type: :movement_speed_changed}), do: entity

  def emit(%Mob{} = entity, %Event{type: :monster_move, move_opts: opts}) do
    Message.SmsgMonsterMove.build(entity, opts || [])
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :monster_move}), do: entity

  def emit(entity, %Event{type: :spell_cast_result, spell_id: spell_id}) do
    Network.send_packet(%Message.SmsgCastResult{
      spell: spell_id,
      result: 0,
      reason: nil,
      required_spell_focus: nil,
      area: nil,
      equipped_item_class: nil,
      equipped_item_subclass_mask: nil,
      equipped_item_inventory_type_mask: nil
    })

    entity
  end

  def emit(%{object: %{guid: guid}} = entity, %Event{type: :spell_go} = event) when is_integer(guid) do
    %Message.SmsgSpellGo{
      cast_item: event.source_guid || guid,
      caster: event.source_guid || guid,
      spell: event.spell_id,
      flags: 0x100,
      hits: event.hit_guids || [],
      misses: [],
      targets: event.raw_targets || <<>>,
      ammo_display_id: nil,
      ammo_inventory_type: nil
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :spell_go}), do: entity

  def emit(%{internal: %Internal{broadcast_update?: true} = internal} = entity, %Event{type: :object_update} = event) do
    Core.update_object(entity, event.update_type || :values)
    |> World.broadcast_packet(entity)

    %{entity | internal: %{internal | broadcast_update?: false}}
  end

  def emit(entity, %Event{type: :object_update}), do: entity

  def emit(entity, %Event{type: :attack_start} = event) do
    %Message.SmsgAttackstart{
      attacker: event.source_guid,
      victim: event.target_guid
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :attacker_state_update} = event) do
    attack = event.attack || %{}
    damage = event.damage || 0

    %Message.SmsgAttackerstateupdate{
      attacker: event.source_guid,
      target: event.target_guid,
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
      damage_state: Map.get(attack, :damage_state, 0),
      unknown1: Map.get(attack, :unknown1, 0),
      spell_id: Map.get(attack, :spell_id, 0),
      blocked_amount: Map.get(attack, :blocked_amount, 0)
    }
    |> World.broadcast_packet(entity)

    entity
  end

  def emit(entity, %Event{type: :attack_not_in_range}) do
    Packet.build(<<>>, Opcodes.get(:SMSG_ATTACKSWING_NOTINRANGE))
    |> Network.send_packet()

    entity
  end

  def emit(entity, %Event{type: :trigger_spell} = event) do
    case SpellLoader.load(event.spell_id) do
      nil ->
        entity

      spell ->
        dispatch_triggered_spell(entity, event, spell)
    end
  end

  def emit(entity, _event), do: entity

  defp dispatch_triggered_spell(%{object: %{guid: guid}} = entity, %Event{target_guid: guid} = event, spell) do
    context = trigger_context(event, spell)
    {entity, events} = SpellEffect.receive(entity, context, spell)
    emit(entity, events)
  end

  defp dispatch_triggered_spell(entity, %Event{} = event, spell) do
    context = trigger_context(event, spell)
    Entity.receive_spell(event.target_guid, context, spell)
    entity
  end

  defp trigger_context(%Event{} = event, spell) do
    %CastContext{
      caster_guid: event.source_guid,
      caster_level: event.source_level || 1,
      target_guid: event.target_guid,
      spell: spell
    }
  end

  defp school_index(:physical), do: 0
  defp school_index(:holy), do: 1
  defp school_index(:fire), do: 2
  defp school_index(:nature), do: 3
  defp school_index(:frost), do: 4
  defp school_index(:shadow), do: 5
  defp school_index(:arcane), do: 6
  defp school_index(other) when is_integer(other), do: other
  defp school_index(_), do: 0
end
