defmodule ThistleTea.Game.Entity.Logic.AttackFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Spell

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
  end
end
