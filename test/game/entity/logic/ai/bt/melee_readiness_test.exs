defmodule ThistleTea.Game.Entity.Logic.AI.BT.MeleeReadinessTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink.Combat, as: CombatSink
  alias ThistleTea.Game.Entity.EventSink.Context, as: SinkContext
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Combat
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.WorldRef

  setup [:attacker]

  describe "melee_attack_with_context/3" do
    test "holds both hands and a queued ability outside the facing arc", %{attacker: attacker, blackboard: blackboard} do
      queued = %Spell{id: 78}
      attacker = %{attacker | internal: %{attacker.internal | next_swing_spell: queued}}
      {:success, result, blackboard} = Combat.melee_attack_with_context(attacker, blackboard, context(-3, 0))
      assert [%Effects.AttackBadFacing{}] = result.internal.events
      assert result.internal.next_swing_spell == queued
      assert result.unit.power2 == 500
      assert blackboard.combat.next_attack_at == 1_100
      assert blackboard.combat.next_offhand_attack_at == 1_100

      {:success, result, blackboard} =
        Combat.melee_attack_with_context(clear_events(result), blackboard, context(-3, 0, 1_100))

      assert result.internal.events == []
      {:success, result, blackboard} = Combat.melee_attack_with_context(result, blackboard, context(20, 0, 1_200))
      assert [%Effects.AttackNotInRange{}] = result.internal.events
      {:success, result, _} = Combat.melee_attack_with_context(clear_events(result), blackboard, context(-3, 0, 1_300))
      assert [%Effects.AttackBadFacing{}] = result.internal.events
    end

    test "uses a 120 degree arc with angle wrapping and overlap tolerance", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      for {orientation, x, y, allowed?} <- [
            {0.0, 3.0, 0.0, true},
            {0.0, 2.0, 3.4, true},
            {0.0, 2.0, 3.5, false},
            {0.0, 0.0, 3.0, false},
            {0.0, -3.0, 0.0, false},
            {0.0, -1.4, 0.0, true},
            {0.0, -1.41, 0.0, false},
            {2 * :math.pi() - 0.1, 3.0, 0.0, true}
          ] do
        attacker = %{attacker | movement_block: %{attacker.movement_block | position: {0.0, 0.0, 0.0, orientation}}}
        {:success, result, _} = Combat.melee_attack_with_context(attacker, blackboard, context(x, y))
        assert Enum.any?(result.internal.events, &is_struct(&1, Effects.DeliverAttack)) == allowed?
      end
    end

    test "retries a ready off hand without changing a future main-hand deadline", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      blackboard = %{blackboard | combat: %{blackboard.combat | next_attack_at: 5_000}}
      {:success, result, blackboard} = Combat.melee_attack_with_context(attacker, blackboard, context(20, 0))
      assert [%Effects.AttackNotInRange{}] = result.internal.events
      assert blackboard.combat.next_attack_at == 5_000
      assert blackboard.combat.next_offhand_attack_at == 1_100

      {:success, result, blackboard} =
        Combat.melee_attack_with_context(clear_events(result), blackboard, context(3, 0, 1_100))

      assert [%Effects.DeliverAttack{attack: %{offhand?: true}}] = result.internal.events
      assert blackboard.combat.next_attack_at == 5_000
      assert blackboard.combat.last_swing_error == nil
    end

    test "an off-hand swing delays an imminent main-hand swing to 200 milliseconds", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      blackboard = %{blackboard | combat: %{blackboard.combat | next_attack_at: 1_050}}
      {:success, result, blackboard} = Combat.melee_attack_with_context(attacker, blackboard, context(3, 0))
      assert [%Effects.DeliverAttack{attack: %{offhand?: true}}] = result.internal.events
      assert blackboard.combat.next_attack_at == 1_200
      assert blackboard.combat.next_offhand_attack_at == 2_500
      assert Combat.next_attack_delay(result, blackboard, 1_000) == 200
    end

    test "stun, confusion, active fear, pacify, and feign death prevent swings", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      for type <- [:mod_stun, :mod_confuse, :mod_fear, :mod_pacify, :mod_pacify_silence, :feign_death] do
        controlled = with_auras(attacker, [type])
        {:success, result, updated} = Combat.melee_attack_with_context(controlled, blackboard, context(3, 0))
        assert result.internal.events == []
        assert updated.combat.next_attack_at == 1_100
        assert updated.combat.next_offhand_attack_at == 1_100
      end

      for types <- [[:mod_root], [:mod_silence], [:mod_fear, :prevent_fleeing]] do
        {:success, result, _} = Combat.melee_attack_with_context(with_auras(attacker, types), blackboard, context(3, 0))
        assert [%Effects.DeliverAttack{}] = result.internal.events
      end
    end

    test "dead attackers, ghosts, dead victims, and concealed victims do not swing", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      dead = %{attacker | unit: %{attacker.unit | health: 0}}
      ghost = %{attacker | player: %{attacker.player | flags: 0x10}}

      for {entity, metadata} <- [
            {dead, %{}},
            {ghost, %{}},
            {attacker, %{alive?: false}},
            {attacker, %{invisibility: %{0 => 100}}}
          ] do
        {:success, result, _} = Combat.melee_attack_with_context(entity, blackboard, context(3, 0, 1_000, metadata))
        assert result.internal.events == []
      end
    end

    test "ordinary swings wait for casting while extra swings preserve the active cast", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      cast = %Cast{spell: %Spell{id: 133}}
      attacker = %{attacker | internal: %{attacker.internal | casting: cast}}
      assert {:success, ^attacker, ^blackboard} = Combat.melee_attack_with_context(attacker, blackboard, context(3, 0))
      pending = %{blackboard | combat: %{blackboard.combat | extra_attacks: 2}}
      {:failure, result, updated} = Combat.consume_extra_attacks(attacker, pending, context(3, 0))
      assert length(result.internal.events) == 2
      assert result.internal.casting == cast
      assert updated.combat.extra_attacks == 0
    end

    test "stationary creatures and pets turn to a melee victim before swinging", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      for pet <- [nil, %Internal.Pet{owner_guid: 3, kind: :hunter}] do
        mob = %Mob{
          object: attacker.object,
          unit: attacker.unit,
          movement_block: attacker.movement_block,
          internal: %{attacker.internal | pet: pet, in_combat: true}
        }

        {:success, result, _} = Combat.melee_attack_with_context(mob, blackboard, context(-4, 0))
        assert_in_delta elem(result.movement_block.position, 3), :math.pi(), 0.001
        assert [%Effects.SetFacing{facing: {:target, 2}}, %Effects.DeliverAttack{}] = result.internal.events
      end
    end
  end

  describe "consume_extra_attacks/3" do
    test "player batches wait for facing and can execute while fear is suppressed", %{
      attacker: attacker,
      blackboard: blackboard
    } do
      pending = %{blackboard | combat: %{blackboard.combat | extra_attacks: 2}}
      assert {:failure, ^attacker, ^pending} = Combat.consume_extra_attacks(attacker, pending, context(-3, 0))
      attacker = with_auras(attacker, [:mod_fear, :prevent_fleeing])
      {:failure, result, updated} = Combat.consume_extra_attacks(attacker, pending, context(3, 0))
      assert length(result.internal.events) == 2
      assert updated.combat.extra_attacks == 0
    end
  end

  describe "clear_auto_attack/1" do
    test "restarting an attack permits fresh error feedback", %{blackboard: blackboard} do
      blackboard = %{blackboard | combat: %{blackboard.combat | last_swing_error: :bad_facing}}
      assert Blackboard.clear_auto_attack(blackboard).combat.last_swing_error == nil
      assert Blackboard.clear_attack(blackboard).combat.last_swing_error == nil
    end
  end

  describe "emit/3" do
    test "swing errors go only to the explicit owner context", %{attacker: attacker} do
      for {effect, packet, opcode} <- [
            {%Effects.AttackBadFacing{}, %Message.SmsgAttackswingBadfacing{}, 0x146},
            {%Effects.AttackNotInRange{}, %Message.SmsgAttackswingNotinrange{}, 0x145}
          ] do
        assert packet.__struct__.opcode() == opcode
        assert packet.__struct__.to_binary(packet) == <<>>
        CombatSink.emit(attacker, effect, nil)
        refute_received {:"$gen_cast", {:send_packet, _}}
        CombatSink.emit(attacker, effect, SinkContext.new(self()))
        assert_received {:"$gen_cast", {:send_packet, ^packet}}
      end
    end
  end

  defp attacker(_context) do
    %{
      attacker: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          target: 2,
          auras: [],
          power2: 500,
          min_damage: 10,
          max_damage: 10,
          base_attack_time: 2_000,
          min_offhand_damage: 6,
          max_offhand_damage: 6,
          offhand_attack_time: 1_500
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{world: WorldRef.open(0)}
      },
      blackboard: %Blackboard{combat: %Blackboard.Combat{attack_started: true, auto_attacking: true}}
    }
  end

  defp context(x, y, now \\ 1_000, metadata \\ %{}) do
    observation = %Observation{
      guid: 2,
      position: {WorldRef.open(0), x * 1.0, y * 1.0, 0.0},
      distance: :math.sqrt(x * x + y * y),
      metadata: Map.merge(%{alive?: true}, metadata)
    }

    Context.new(now, perception: Perception.new(now, nil, %{2 => observation}, %{mobs: [], players: []}))
  end

  defp clear_events(entity), do: %{entity | internal: %{entity.internal | events: []}}

  defp with_auras(entity, types) do
    holders = Enum.map(types, &%Holder{spell: %Spell{id: 1}, auras: [%Aura{type: &1}]})
    %{entity | unit: %{entity.unit | auras: holders}}
  end
end
