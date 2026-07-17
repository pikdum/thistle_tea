defmodule ThistleTea.Game.Entity.Logic.AttackFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  defp warrior(level \\ 60) do
    %Mob{
      unit: %Unit{power_type: 1, level: level, power2: 0, max_power2: 1_000, auras: []},
      internal: %Internal{}
    }
  end

  describe "receive/3" do
    test "grants dealt rage on a landed swing" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :normal, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 65
    end

    test "grants reduced rage when the swing is dodged" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :dodge, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 48
    end

    test "grants reduced rage when the swing is parried" do
      entity = AttackFeedback.receive(warrior(), %{outcome: :parry, damage: 200, spell_id: nil}, 1_000)

      assert entity.unit.power2 == 48
    end

    test "grants nothing on a miss" do
      entity = warrior()

      assert AttackFeedback.receive(entity, %{outcome: :miss, damage: 0, spell_id: nil}, 1_000) == entity
    end

    test "swings carrying a queued spell grant no rage" do
      entity = warrior()

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: 78}, 1_000) == entity
    end

    test "dodged rage abilities refund 82 percent of the cost" do
      entity = warrior()

      spell = %Spell{
        id: 78,
        mana_cost: 150,
        power_type: 1,
        attributes: MapSet.new([:discount_power_on_miss])
      }

      entity = AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, spell_id: 78}, spell, 1_000)

      assert entity.unit.power2 == 123
    end

    test "abilities without the refund attribute get nothing back on dodge" do
      entity = warrior()
      spell = %Spell{id: 78, mana_cost: 150, power_type: 1}

      assert AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, spell_id: 78}, spell, 1_000) == entity
    end

    test "abilities that land grant no rage even with the spell known" do
      entity = warrior()

      spell = %Spell{
        id: 78,
        mana_cost: 150,
        power_type: 1,
        attributes: MapSet.new([:discount_power_on_miss])
      }

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: 78}, spell, 1_000) == entity
    end

    test "ignores non-rage users" do
      entity = %Mob{
        unit: %Unit{power_type: 0, level: 60, power1: 0, max_power1: 100},
        internal: %Internal{}
      }

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: nil}, 1_000) == entity
    end

    test "a dodging target earns the warrior a combo point for overpower" do
      entity = %Character{
        object: %Object{guid: 5},
        unit: %Unit{class: 1, power_type: 1, level: 60, power2: 0, max_power2: 1_000, auras: []},
        player: %Player{},
        internal: %Internal{}
      }

      payload = %{outcome: :dodge, damage: 100, spell_id: nil, victim_guid: 77}
      entity = AttackFeedback.receive(entity, payload, nil, 1_000)

      assert entity.player.field_combo_target == 77
      assert entity.player.combo_points == 1
    end

    test "rogue builders grant points only after landing" do
      entity = rogue()
      spell = %Spell{id: 1757, effects: [%Effect{type: :add_combo_points, base_points: 0, die_sides: 1}]}

      landed = AttackFeedback.receive(entity, %{outcome: :normal, damage: 20, victim_guid: 77}, spell, 1_000)
      avoided = AttackFeedback.receive(entity, %{outcome: :dodge, damage: 0, victim_guid: 77}, spell, 1_000)

      assert landed.player.combo_points == 1
      assert avoided.player.combo_points in [nil, 0]
    end

    test "finishers consume points on hit but retain them on avoidance" do
      entity = Reactive.add_combo_points(rogue(), 77, 5)
      spell = %Spell{id: 6760, name: "Eviscerate", power_type: 3, mana_cost: 35}

      landed = AttackFeedback.receive(entity, %{outcome: :normal, damage: 500, victim_guid: 77}, spell, 1_000)
      avoided = AttackFeedback.receive(entity, %{outcome: :parry, damage: 0, victim_guid: 77}, spell, 1_000)

      assert landed.player.combo_points == 0
      assert landed.player.field_combo_target == 77
      assert avoided.player.combo_points == 5
    end

    test "missed finishers retain points and refund eighty percent of their energy" do
      entity = rogue()
      entity = %{entity | unit: %{entity.unit | power4: 65}}
      entity = Reactive.add_combo_points(entity, 77, 5)
      spell = %Spell{id: 6760, name: "Eviscerate", power_type: 3, mana_cost: 35}

      entity = AttackFeedback.receive(entity, %{outcome: :miss, damage: 0, victim_guid: 77}, spell, 1_000)

      assert entity.player.combo_points == 5
      assert entity.unit.power4 == 93
    end

    test "gouge stops the rogue's auto attack when it lands" do
      entity = rogue()
      spell = %Spell{id: 1776, name: "Gouge"}

      entity = AttackFeedback.receive(entity, %{outcome: :normal, damage: 10, victim_guid: 77}, spell, 1_000)

      refute entity.internal.blackboard.auto_attacking
      assert Enum.any?(entity.internal.events, &(&1.type == :attack_stop))
    end

    test "scatter shot stops auto attack when it lands" do
      entity = rogue()
      spell = %Spell{id: 19_503, name: "Scatter Shot"}

      entity = AttackFeedback.receive(entity, %{outcome: :normal, damage: 10, victim_guid: 77}, spell, 1_000)

      refute entity.internal.blackboard.auto_attacking
      assert Enum.any?(entity.internal.events, &(&1.type == :attack_stop))
    end

    test "blade flurry queues a secondary strike from landed damage" do
      blade_flurry = %Spell{
        id: 13_877,
        duration_ms: 15_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_melee_haste, base_points: 20}]
      }

      {entity, _events} = Aura.apply_spell(rogue(), 5, 60, blade_flurry, 1_000)
      entity = AttackFeedback.receive(entity, %{outcome: :normal, damage: 123, victim_guid: 77}, nil, 1_000)

      assert Enum.any?(entity.internal.events, &match?(%{type: :blade_flurry, target_guid: 77, damage: 123}, &1))
    end
  end

  defp rogue do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{class: 4, level: 60, power_type: 3, power4: 100, max_power4: 100, auras: []},
      player: %Player{},
      internal: %Internal{blackboard: %Blackboard{auto_attacking: true, attack_started: true}}
    }
  end
end
