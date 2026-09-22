defmodule ThistleTea.Game.Entity.Logic.CombatControlTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatControl
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "apply_spell/5" do
    test "combined control projects both flags without restricting movement", %{entity: entity} do
      entity = apply_control(entity, :mod_pacify_silence, 1)
      assert CombatControl.pacified?(entity)
      assert CombatControl.silenced?(entity)
      assert (entity.unit.flags &&& 0x22008) == 0x22008
      refute entity.internal.rooted?
    end

    test "overlapping independent controls survive combined control removal", %{entity: entity} do
      entity =
        entity
        |> apply_control(:mod_pacify_silence, 1)
        |> apply_control(:mod_pacify, 2)
        |> apply_control(:mod_silence, 3)

      {entity, _} = Aura.remove_spells(entity, [1], 10)
      assert (entity.unit.flags &&& 0x22000) == 0x22000
      {entity, _} = Aura.remove_spells(entity, [2], 20)
      assert (entity.unit.flags &&& 0x22000) == 0x2000
      {entity, _} = Aura.remove_spells(entity, [3], 30)
      assert entity.unit.flags == 8
    end

    test "removing independent controls preserves combined control", %{entity: entity} do
      entity =
        entity
        |> apply_control(:mod_pacify, 1)
        |> apply_control(:mod_silence, 2)
        |> apply_control(:mod_pacify_silence, 3)

      {entity, _} = Aura.remove_spells(entity, [1, 2], 10)
      assert (entity.unit.flags &&& 0x22000) == 0x22000
    end

    test "silence interrupts only silence-prevented casts and emits failure", %{entity: entity} do
      for aura <- [:mod_silence, :mod_pacify_silence], prevention <- [0, 1, 2] do
        spell = %Spell{id: 100, prevention_type: prevention, cast_time_ms: 5_000}
        casting = Cast.new(spell, Target.unit(2), 0)
        caster = %{entity | internal: %{entity.internal | casting: casting}}
        caster = apply_control(caster, aura, 1)
        assert is_nil(caster.internal.casting) == (prevention == 1)

        assert Enum.any?(
                 caster.internal.events,
                 &match?(%Effects.SpellCastFailed{spell_id: 100, reason: :interrupted}, &1)
               ) == (prevention == 1)
      end
    end

    test "interrupted channels release objects, remote auras, and client timers", %{entity: entity} do
      spell = %Spell{id: 100, prevention_type: 1, duration_ms: 5_000, attributes: MapSet.new([:channeled])}
      casting = %{Cast.new(spell, Target.unit(2), 0) | phase: :channel_tick}

      entity = %{
        entity
        | unit: %{entity.unit | channel_spell: 100, channel_object: 2},
          internal: %{
            entity.internal
            | casting: casting,
              channel_game_object_guid: 55,
              channel_game_object_owned?: true
          }
      }

      entity = apply_control(entity, :mod_pacify_silence, 1)
      assert entity.internal.casting == nil
      assert entity.internal.channel_game_object_guid == nil
      assert entity.unit.channel_spell == 0
      assert entity.unit.channel_object == 0
      assert Enum.any?(entity.internal.events, &match?(%Effects.ChannelUpdate{channel_time_ms: 0}, &1))
      assert Enum.any?(entity.internal.events, &match?(%Effects.DespawnEntity{target_guid: 55}, &1))
      assert Enum.any?(entity.internal.events, &match?(%Effects.RemoveAura{target_guid: 2, spell_id: 100}, &1))
    end

    test "pacify alone does not interrupt a magical cast", %{entity: entity} do
      casting = Cast.new(%Spell{id: 100, prevention_type: 1}, Target.unit(2), 0)
      entity = %{entity | internal: %{entity.internal | casting: casting}}
      assert apply_control(entity, :mod_pacify, 1).internal.casting == casting
    end
  end

  describe "expire_due/2" do
    test "refresh keeps control until the refreshed deadline", %{entity: entity} do
      entity = apply_control(entity, :mod_pacify_silence, 1)
      {entity, _} = Aura.apply_spell(entity, 2, 10, control(:mod_pacify_silence, 1), 500)
      {entity, _} = Aura.expire_due(entity, 1_000)
      assert CombatControl.pacified?(entity)
      {entity, _} = Aura.expire_due(entity, 1_500)
      refute CombatControl.pacified?(entity)
      refute CombatControl.silenced?(entity)
      assert entity.unit.flags == 8
    end
  end

  describe "take_damage/4" do
    test "death clears control and its flags", %{entity: entity} do
      entity = entity |> apply_control(:mod_pacify_silence, 1) |> Core.take_damage(100, 100)
      assert entity.unit.health == 0
      refute CombatControl.pacified?(entity)
      refute CombatControl.silenced?(entity)
      assert (entity.unit.flags &&& 0x22000) == 0
    end
  end

  describe "validate/5" do
    test "combined control respects each spell prevention type", %{entity: entity} do
      entity = apply_control(entity, :mod_pacify_silence, 1)

      for {prevention, result} <- [{0, :ok}, {1, {:error, :silenced}}, {2, {:error, :pacified}}] do
        spell = %Spell{id: 100, prevention_type: prevention}
        assert CastValidation.validate(entity, spell, Target.self(1), nil, 10) == result
      end
    end
  end

  describe "receive/4" do
    test "state immunity blocks the combined effect with immune feedback", %{entity: entity} do
      protection = %Spell{
        id: 99,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :state_immunity, misc_value: :mod_pacify_silence}]
      }

      {entity, _} = Aura.apply_spell(entity, 1, 10, protection, 0)
      {entity, events} = SpellEffect.receive(entity, 2, control(:mod_pacify_silence, 1), 10)
      refute CombatControl.pacified?(entity)
      assert [%Effects.SpellLogMiss{reason: :immune}] = events
    end
  end

  describe "melee_attack_with_context/3" do
    test "pacify pauses both hands and queued abilities until removed", %{entity: entity} do
      context = combat_context()
      queued = %Spell{id: 78}
      entity = %{entity | internal: %{entity.internal | next_swing_spell: queued}}
      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true}}

      for aura <- [:mod_pacify, :mod_pacify_silence] do
        controlled = apply_control(entity, aura, 1)
        {:success, controlled, updated} = Combat.melee_attack_with_context(controlled, blackboard, context)
        assert controlled.internal.events == []
        assert controlled.internal.next_swing_spell == queued
        assert updated == blackboard
        pending = %{blackboard | combat: %{blackboard.combat | extra_attacks: 2}}
        {:failure, controlled, ^pending} = Combat.consume_extra_attacks(controlled, pending, context)
        assert controlled.internal.events == []
        {released, _} = Aura.remove_spells(controlled, [1], 100)
        released = %{released | internal: %{released.internal | next_swing_spell: nil}}
        {:success, released, _} = Combat.melee_attack_with_context(released, blackboard, context)
        assert Enum.count(released.internal.events, &is_struct(&1, Effects.DeliverAttack)) == 2
      end
    end

    test "silence alone leaves melee attacks available", %{entity: entity} do
      entity = apply_control(entity, :mod_silence, 1)
      blackboard = %Blackboard{combat: %Blackboard.Combat{attack_started: true}}
      {:success, entity, _} = Combat.melee_attack_with_context(entity, blackboard, combat_context())
      assert Enum.count(entity.internal.events, &is_struct(&1, Effects.DeliverAttack)) == 2
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 10,
          flags: 8,
          auras: [],
          target: 2,
          min_damage: 5,
          max_damage: 5,
          base_attack_time: 2_000,
          min_offhand_damage: 3,
          max_offhand_damage: 3,
          offhand_attack_time: 2_000,
          combat_reach: 1.5
        },
        internal: %Internal{world: WorldRef.open(0)},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp apply_control(entity, type, id) do
    {entity, _} = Aura.apply_spell(entity, 2, 10, control(type, id), 0)
    entity
  end

  defp control(type, id) do
    %Spell{
      id: id,
      duration_ms: 1_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, implicit_target_a: :target_enemy}]
    }
  end

  defp combat_context do
    observation = %Observation{
      guid: 2,
      position: {WorldRef.open(0), 1.0, 0.0, 0.0},
      distance: 1.0,
      line_of_sight?: true,
      metadata: %{combat_reach: 1.5}
    }

    Context.new(100, perception: Perception.new(100, nil, %{2 => observation}, %{mobs: [], players: []}))
  end
end
