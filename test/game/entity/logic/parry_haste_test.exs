defmodule ThistleTea.Game.Entity.Logic.ParryHasteTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ParryHaste

  @now -10_000

  describe "Combat.receive_attack/4" do
    test "a parried swing advances the defender and reports zero damage" do
      entity = defender(2_000)
      entity = %{entity | object: %Object{guid: 100}, unit: %{entity.unit | health: 100, level: 20}}
      attack = %{caster: 1, caster_level: 20, caster_player?: true, damage: 10}

      {result, events} = Combat.receive_attack(entity, attack, @now, roll: 1_000)

      assert result.unit.health == 100
      assert result.internal.blackboard.combat.next_attack_at == @now + 1_200
      assert [%Effects.AttackerStateUpdate{damage: 0, attack: %{damage_state: 3}} | _] = events
    end

    test "a ranged attack cannot trigger parry haste" do
      entity = defender(2_000)
      entity = %{entity | object: %Object{guid: 100}, unit: %{entity.unit | health: 100, level: 20}}
      attack = %{caster: 1, caster_level: 20, caster_player?: true, damage: 0, ranged?: true}

      {result, _events} = Combat.receive_attack(entity, attack, @now, roll: 1_000)

      assert result.internal.blackboard == entity.internal.blackboard
    end
  end

  describe "apply/3" do
    test "removes forty percent of the weapon period" do
      entity = defender(2_000)
      result = ParryHaste.apply(entity, :parry, @now)
      assert result.internal.blackboard.combat.next_attack_at == @now + 1_200
      assert result.unit == entity.unit
    end

    test "floors shortened swings at twenty percent" do
      for remaining <- [401, 700, 1_200] do
        result = ParryHaste.apply(defender(remaining), :parry, @now)
        assert result.internal.blackboard.combat.next_attack_at == @now + 400
      end
    end

    test "leaves imminent and overdue swings unchanged" do
      for remaining <- [-100, 0, 100, 400] do
        entity = defender(remaining)
        assert ParryHaste.apply(entity, :parry, @now) == entity
      end
    end

    test "repeated parries cannot cross the floor" do
      result = Enum.reduce(1..5, defender(2_000), fn _, entity -> ParryHaste.apply(entity, :parry, @now) end)
      assert result.internal.blackboard.combat.next_attack_at == @now + 400
    end

    test "uses the unmodified weapon period under melee haste" do
      entity = defender(1_000)
      holder = %Holder{auras: [%Aura{type: :mod_melee_haste, amount: 100}]}
      entity = %{entity | unit: %{entity.unit | auras: [holder]}}

      assert Combat.attack_speed_ms(entity) == 1_000
      result = ParryHaste.apply(entity, :parry, @now)
      assert result.internal.blackboard.combat.next_attack_at == @now + 400
    end

    test "advances only the earlier offhand using its own period" do
      entity = dual_wielder(2_000, 1_000)
      result = ParryHaste.apply(entity, :parry, @now)
      assert result.internal.blackboard.combat.next_offhand_attack_at == @now + 600
      assert result.internal.blackboard.combat.next_attack_at == @now + 2_000
    end

    test "equal hand deadlines favor main hand" do
      result = ParryHaste.apply(dual_wielder(1_000, 1_000), :parry, @now)
      assert result.internal.blackboard.combat.next_attack_at == @now + 400
      assert result.internal.blackboard.combat.next_offhand_attack_at == @now + 1_000
    end

    test "an imminent offhand does not transfer haste to main hand" do
      entity = dual_wielder(2_000, 100)
      assert ParryHaste.apply(entity, :parry, @now) == entity
    end

    test "ignores offhand timers without an offhand weapon" do
      entity = defender(2_000, 500)
      result = ParryHaste.apply(entity, :parry, @now)
      assert result.internal.blackboard.combat.next_attack_at == @now + 1_200
      assert result.internal.blackboard.combat.next_offhand_attack_at == @now + 500
    end

    test "does not create timers or haste other outcomes" do
      entity = %Mob{unit: %Unit{base_attack_time: 2_000}, internal: %Internal{blackboard: %Blackboard{}}}
      assert ParryHaste.apply(entity, :parry, @now) == entity
      assert ParryHaste.apply(%Mob{}, :parry, @now) == %Mob{}

      for outcome <- [:dodge, :block, :miss, :normal, :crit] do
        entity = defender(2_000)
        assert ParryHaste.apply(entity, outcome, @now) == entity
      end
    end
  end

  defp defender(main, offhand \\ 0) do
    blackboard = %Blackboard{}
    combat = %{blackboard.combat | next_attack_at: @now + main, next_offhand_attack_at: @now + offhand}

    %Mob{
      unit: %Unit{base_attack_time: 2_000},
      internal: %Internal{blackboard: %{blackboard | combat: combat}}
    }
  end

  defp dual_wielder(main, offhand) do
    entity = defender(main, offhand)
    %{entity | unit: %{entity.unit | offhand_attack_time: 1_000, min_offhand_damage: 5, max_offhand_damage: 10}}
  end
end
