defmodule ThistleTea.Game.Entity.Logic.AttackTimersTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AttackTimers
  alias ThistleTea.Game.Entity.Logic.AutoRepeat
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Target

  setup [:combatant]

  describe "equipment_changed/3" do
    test "a mainhand swap restarts its full new period and retains the other hand", %{character: character} do
      changed = swap_mainhand(character, 3_400)
      result = AttackTimers.equipment_changed(changed, character, 1_000)
      assert result.internal.blackboard.combat.next_attack_at == 4_400
      assert result.internal.blackboard.combat.next_offhand_attack_at == 1_700
      assert result.internal.blackboard.combat.extra_attacks == 2
      assert result.internal.broadcast_update?
      assert result.internal.events == []
    end

    test "another instance of the same weapon also resets a ready swing", %{character: character} do
      changed = %{character | player: %{character.player | mainhand: 99}}
      result = AttackTimers.equipment_changed(changed, character, 5_000)
      assert result.internal.blackboard.combat.next_attack_at == 7_000
    end

    test "the reset uses the hasted new period with negative monotonic time", %{character: character} do
      haste = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: :mod_melee_haste, amount: 100}]}
      character = %{character | unit: Stats.recompute(%{character.unit | auras: [haste]})}
      changed = swap_mainhand(character, 3_400)
      result = AttackTimers.equipment_changed(changed, character, -100_000)
      assert result.unit.base_attack_time == 1_700
      assert result.internal.blackboard.combat.next_attack_at == -98_300
      refute Blackboard.ready_for?(result.internal.blackboard, :next_attack_at, -98_301)
      assert Blackboard.ready_for?(result.internal.blackboard, :next_attack_at, -98_300)
    end

    test "two-handed replacement resets the removed offhand independently", %{character: character} do
      changed = swap_mainhand(character, 3_800)
      unit = %{changed.unit | offhand_weapon: nil, base_offhand_attack_time: 2_000} |> Stats.recompute()
      changed = %{changed | unit: unit, player: %{changed.player | offhand: 0}}
      result = AttackTimers.equipment_changed(changed, character, 1_000)
      assert result.internal.blackboard.combat.next_attack_at == 4_800
      assert result.internal.blackboard.combat.next_offhand_attack_at == 3_000
    end

    test "unequipping a mainhand starts the unarmed period", %{character: character} do
      unit = %{character.unit | mainhand_weapon: nil, base_melee_attack_time: 2_000} |> Stats.recompute()
      changed = %{character | unit: unit, player: %{character.player | mainhand: 0}}
      result = AttackTimers.equipment_changed(changed, character, 1_000)
      assert result.internal.blackboard.combat.next_attack_at == 3_000
    end

    test "broken and repaired weapons reset only when availability changes", %{character: character} do
      broken = %{character | player: %{character.player | broken_equipment: [:mainhand]}}
      result = AttackTimers.equipment_changed(broken, character, 1_000)
      assert result.internal.blackboard.combat.next_attack_at == 3_000
      assert AttackTimers.equipment_changed(result, result, 1_500) == result
      repaired = %{result | player: %{result.player | broken_equipment: []}}
      assert AttackTimers.equipment_changed(repaired, result, 2_000).internal.blackboard.combat.next_attack_at == 4_000
    end

    test "feral forms and disarmed mainhands do not restart natural attacks", %{character: character} do
      for form <- [1, 5, 8] do
        character = %{character | unit: %{character.unit | class: 11, shapeshift_form: form}}
        changed = swap_mainhand(character, 3_400)
        assert AttackTimers.equipment_changed(changed, character, 1_000) == changed
      end

      holder = %Holder{spell: %Spell{id: 676}, auras: [%Aura{type: :mod_disarm}]}
      character = %{character | unit: %{character.unit | auras: [holder]}}
      changed = swap_mainhand(character, 3_400)
      assert AttackTimers.equipment_changed(changed, character, 1_000) == changed
    end

    test "peaceful, dead and non-weapon changes preserve timers", %{character: character} do
      peaceful = %{character | internal: %{character.internal | in_combat: false}}
      dead = %{character | unit: %{character.unit | health: 0}}

      for character <- [peaceful, dead] do
        changed = swap_mainhand(character, 3_400)
        assert AttackTimers.equipment_changed(changed, character, 1_000) == changed
      end

      for player <- [%{character.player | head: 99}, %{character.player | inv1: 99}] do
        changed = %{character | player: player}
        assert AttackTimers.equipment_changed(changed, character, 1_000) == changed
      end
    end

    test "ordinary haste and slow recomputation leaves an in-progress swing intact", %{character: character} do
      for amount <- [100, -25] do
        holder = %Holder{spell: %Spell{id: 1}, auras: [%Aura{type: :mod_melee_haste, amount: amount}]}
        changed = %{character | unit: Stats.recompute(%{character.unit | auras: [holder]})}
        assert AttackTimers.equipment_changed(changed, character, 1_000) == changed
      end
    end

    test "ranged swaps reset both live and retained shot deadlines and invalidate pending launches", %{
      character: character
    } do
      shot = %{
        spell: %Spell{id: 75},
        targets: Target.unit(50),
        target_guid: 50,
        next_at: 1_200,
        pending?: true,
        paused?: true
      }

      character = %{character | internal: %{character.internal | auto_shot: shot, ranged_attack_at: 1_200}}

      changed = %{
        character
        | player: %{character.player | ranged: 99},
          unit: %{character.unit | ranged_attack_time: 2_500}
      }

      result = AttackTimers.equipment_changed(changed, character, 1_000)
      assert result.internal.ranged_attack_at == 3_500
      assert result.internal.auto_shot == shot |> Map.put(:next_at, 3_500) |> Map.delete(:pending?)
      assert result.internal.blackboard == character.internal.blackboard
      {stopped, _events} = AutoRepeat.cancel(result)
      resumed = AutoRepeat.start(stopped, shot.spell, shot.targets, 1_100)
      assert resumed.internal.auto_shot.next_at == 3_500
    end

    test "a combat ranged swap before starting auto shot still delays the first shot", %{character: character} do
      changed = %{character | player: %{character.player | ranged: 99}}
      result = AttackTimers.equipment_changed(changed, character, 1_000)
      assert result.internal.auto_shot == nil
      assert result.internal.ranged_attack_at == 4_000
      started = AutoRepeat.start(result, %Spell{id: 75}, Target.unit(50), 1_500)
      assert started.internal.auto_shot.next_at == 4_000
    end

    test "stopping melee attack cannot bypass the restarted weapon timer", %{character: character} do
      result = AttackTimers.equipment_changed(swap_mainhand(character, 3_400), character, 1_000)
      {stopped, _events} = PlayerCombat.stop_melee_attack(result)
      assert stopped.internal.blackboard.combat.next_attack_at == 4_400
    end
  end

  defp combatant(_context) do
    weapon = %ItemTemplate{entry: 1, class: 2, delay: 2_000}

    unit =
      %Unit{
        health: 100,
        class: 1,
        target: 50,
        mainhand_weapon: weapon,
        offhand_weapon: %{weapon | entry: 2, delay: 1_500},
        ranged_weapon: %{weapon | entry: 3, delay: 3_000},
        base_melee_attack_time: 2_000,
        base_offhand_attack_time: 1_500,
        base_ranged_attack_time: 3_000
      }
      |> Stats.recompute()

    blackboard = Blackboard.new()

    blackboard = %{
      blackboard
      | combat: %{blackboard.combat | next_attack_at: 1_200, next_offhand_attack_at: 1_700, extra_attacks: 2}
    }

    character = %Character{
      object: %Object{guid: 1},
      player: %Player{mainhand: 10, offhand: 20, ranged: 30},
      unit: unit,
      internal: %Internal{in_combat: true, blackboard: blackboard}
    }

    %{character: character}
  end

  defp swap_mainhand(character, delay) do
    weapon = %{character.unit.mainhand_weapon | entry: 4, delay: delay}
    unit = %{character.unit | mainhand_weapon: weapon, base_melee_attack_time: delay} |> Stats.recompute()
    %{character | player: %{character.player | mainhand: 40}, unit: unit}
  end
end
