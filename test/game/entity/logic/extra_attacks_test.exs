defmodule ThistleTea.Game.Entity.Logic.ExtraAttacksTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entity]

  describe "grant/3" do
    test "banks one batch without a victim and rejects stacking or recursive grants", %{entity: entity} do
      entity = %{entity | unit: %{entity.unit | target: 0}}
      banked = ExtraAttacks.grant(entity, 2)
      assert banked.internal.blackboard.combat.extra_attacks == 2
      assert banked.internal.events == []
      assert ExtraAttacks.grant(banked, 3) == banked
      assert ExtraAttacks.grant(entity, 2, true) == entity
      dead = %{entity | unit: %{entity.unit | health: 0}}
      assert ExtraAttacks.grant(dead, 2) == dead
      ghost = %Character{unit: %{entity.unit | health: 1}, player: %Player{flags: 0x10}, internal: entity.internal}
      assert ExtraAttacks.grant(ghost, 2) == ghost
    end
  end

  describe "consume_extra_attacks/3" do
    test "uses main-hand white attacks, preserves casting and queued abilities, and resets its timer", %{entity: entity} do
      queued = %Spell{id: 78}
      cast = %Cast{spell: %Spell{id: 133}}
      entity = %{entity | internal: %{entity.internal | next_swing_spell: queued, casting: cast}}
      entity = ExtraAttacks.grant(entity, 2)
      blackboard = entity.internal.blackboard
      {:failure, entity, updated} = Combat.consume_extra_attacks(entity, blackboard, context())
      attacks = Enum.filter(entity.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert length(attacks) == 2

      for %Effects.DeliverAttack{target_guid: 2, attack: attack} <- attacks do
        assert attack.extra_attack?
        refute Map.get(attack, :offhand?, false)
        refute Map.get(attack, :queued_spell_id)
        assert attack.damage == 10
      end

      assert entity.internal.next_swing_spell == queued
      assert entity.internal.casting == cast
      assert updated.combat.extra_attacks == 0
      assert updated.combat.next_attack_at == 3_000
      assert updated.combat.next_offhand_attack_at == 9_000
      entity = %{entity | internal: %{entity.internal | events: []}}
      assert {:failure, ^entity, ^updated} = Combat.consume_extra_attacks(entity, updated, context())
    end

    test "waits for range, a live visible victim, and attack readiness", %{entity: entity} do
      entity = ExtraAttacks.grant(entity, 2)

      unavailable = [context(20), context(3, %{alive?: false}), context(3, %{invisibility: %{0 => 100}})]

      for context <- unavailable do
        assert {:failure, ^entity, blackboard} =
                 Combat.consume_extra_attacks(entity, entity.internal.blackboard, context)

        assert blackboard.combat.extra_attacks == 2
      end

      idle = %{entity | internal: %{entity.internal | in_combat: false}}
      assert {:failure, ^idle, _} = Combat.consume_extra_attacks(idle, idle.internal.blackboard, context())

      for type <- [:mod_stun, :mod_pacify, :mod_confuse, :mod_fear] do
        spell = %Spell{id: 1, effects: [%Effect{index: 0, type: :apply_aura, aura: type}]}
        {controlled, _events} = Aura.apply_spell(entity, 1, 60, spell, 0)

        assert {:failure, ^controlled, _} =
                 Combat.consume_extra_attacks(controlled, controlled.internal.blackboard, context())
      end
    end

    test "ignores facing inside vanilla's overlap distance", %{entity: entity} do
      entity = ExtraAttacks.grant(entity, 1)
      {:failure, entity, blackboard} = Combat.consume_extra_attacks(entity, entity.internal.blackboard, context(-1))
      assert Enum.any?(entity.internal.events, &is_struct(&1, Effects.DeliverAttack))
      assert blackboard.combat.extra_attacks == 0
    end
  end

  describe "plan/3" do
    test "wakes before a long swing or cast delay", %{entity: entity} do
      entity = ExtraAttacks.grant(entity, 2)
      assert Tick.player_delay(entity, {:running, 3_000}, 1_000) == 100
      assert Tick.mob_delay(entity, {:running, 3_000}, 1_000) == 100
    end
  end

  describe "clear/1" do
    test "combat stop, death, and mount clear pending attacks", %{entity: entity} do
      entity = ExtraAttacks.grant(entity, 2)

      character = %Character{
        object: entity.object,
        unit: entity.unit,
        internal: entity.internal,
        player: %Player{},
        movement_block: entity.movement_block
      }

      {stopped, _} = PlayerCombat.stop_attack(character)
      refute ExtraAttacks.pending?(stopped)
      {disengaged, _} = PlayerCombat.disengage(character)
      refute ExtraAttacks.pending?(disengaged)

      for target <- [entity, character] do
        dead = Core.take_damage(target, 100, 1_000)
        refute ExtraAttacks.pending?(dead)
        mount = %Spell{id: 2, effects: [%Effect{index: 0, type: :apply_aura, aura: :mounted, misc_value: 123}]}
        {mounted, _} = Aura.apply_spell(target, 1, 60, mount, 1_000)
        refute ExtraAttacks.pending?(mounted)
      end
    end

    test "passive combat synchronization preserves banked attacks while auto-attack is off", %{entity: entity} do
      entity = ExtraAttacks.grant(entity, 1)
      character = %Character{object: entity.object, unit: entity.unit, internal: entity.internal, player: %Player{}}
      {_, blackboard} = PlayerCombat.sync(character, entity.internal.blackboard, 1_000)
      assert blackboard.combat.extra_attacks == 1
    end
  end

  defp entity(_context) do
    %{
      entity: %Mob{
        object: %Object{guid: 1},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          auras: [],
          target: 2,
          min_damage: 10,
          max_damage: 10,
          base_attack_time: 2_000,
          min_offhand_damage: 3,
          max_offhand_damage: 3,
          offhand_attack_time: 1_000,
          combat_reach: 1.5
        },
        internal: %Internal{
          world: WorldRef.open(0),
          in_combat: true,
          blackboard: %Blackboard{combat: %Blackboard.Combat{next_attack_at: 5_000, next_offhand_attack_at: 9_000}}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp context(x \\ 3, metadata \\ %{}) do
    observation = %Observation{
      guid: 2,
      position: {WorldRef.open(0), x * 1.0, 0.0, 0.0},
      distance: abs(x),
      line_of_sight?: true,
      metadata: Map.merge(%{combat_reach: 1.5, alive?: true}, metadata)
    }

    Context.new(1_000, perception: Perception.new(1_000, nil, %{2 => observation}, %{mobs: [], players: []}))
  end
end
