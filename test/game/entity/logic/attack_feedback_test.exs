defmodule ThistleTea.Game.Entity.Logic.AttackFeedbackTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback

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

    test "ignores non-rage users" do
      entity = %Mob{
        unit: %Unit{power_type: 0, level: 60, power1: 0, max_power1: 100},
        internal: %Internal{}
      }

      assert AttackFeedback.receive(entity, %{outcome: :normal, damage: 200, spell_id: nil}, 1_000) == entity
    end
  end
end
