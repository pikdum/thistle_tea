defmodule ThistleTea.Game.Entity.Logic.ResourcesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell

  defp rage_user(opts \\ []) do
    %Mob{
      unit: %Unit{
        power_type: 1,
        level: Keyword.get(opts, :level, 1),
        power2: Keyword.get(opts, :rage, 0),
        max_power2: 1_000,
        auras: Keyword.get(opts, :auras, [])
      },
      internal: %Internal{}
    }
  end

  describe "rage_conversion/1" do
    test "matches the vanilla formula" do
      assert_in_delta Resources.rage_conversion(1), 7.5, 0.001
      assert_in_delta Resources.rage_conversion(30), 109.2329, 0.001
      assert_in_delta Resources.rage_conversion(60), 230.5993, 0.001
    end

    test "falls back to level 1 for missing levels" do
      assert Resources.rage_conversion(nil) == Resources.rage_conversion(1)
    end
  end

  describe "gain_attack_rage/3" do
    test "converts dealt damage into rage" do
      entity = Resources.gain_attack_rage(rage_user(), 12, :dealt)

      assert entity.unit.power2 == 119
      assert entity.internal.broadcast_update? == true
    end

    test "dealt rage scales down with level" do
      entity = Resources.gain_attack_rage(rage_user(level: 60), 200, :dealt)

      assert entity.unit.power2 == 65
    end

    test "taken damage grants a third as much rage as dealt" do
      entity = Resources.gain_attack_rage(rage_user(level: 60), 200, :taken)

      assert entity.unit.power2 == 21
    end

    test "berserker rage boosts rage from damage taken" do
      auras = [%Holder{spell: %Spell{id: 18_499}, auras: []}]
      entity = Resources.gain_attack_rage(rage_user(level: 60, auras: auras), 200, :taken)

      assert entity.unit.power2 == 28
    end

    test "ignores non-rage users" do
      entity = %Mob{
        unit: %Unit{power_type: 0, level: 1, power1: 10, max_power1: 100, power2: 0, max_power2: 0},
        internal: %Internal{}
      }

      assert Resources.gain_attack_rage(entity, 100, :dealt) == entity
      assert Resources.gain_attack_rage(entity, 100, :taken) == entity
    end
  end

  describe "gain_rage/2" do
    test "adds rage up to the rage cap" do
      entity = Resources.gain_rage(rage_user(rage: 950), 100)

      assert entity.unit.power2 == 1_000
      assert entity.internal.broadcast_update? == true
    end

    test "ignores non-rage users" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 10, max_power1: 100, power2: 0, max_power2: 0},
        internal: %Internal{}
      }

      assert Resources.gain_rage(entity, 100) == entity
    end
  end

  describe "gain_power/3" do
    test "adds power clamped to the maximum" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 90, max_power1: 100},
        internal: %Internal{}
      }

      entity = Resources.gain_power(entity, 0, 30)

      assert entity.unit.power1 == 100
      assert entity.internal.broadcast_update? == true
    end

    test "ignores power types the unit does not have" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 50, max_power1: 100, power4: 0, max_power4: 0},
        internal: %Internal{}
      }

      assert Resources.gain_power(entity, 3, 30) == entity
    end
  end

  describe "spend_power/3" do
    test "deducts mana and records the mana use time" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 100, max_power1: 100},
        internal: %Internal{}
      }

      entity = Resources.spend_power(entity, %Spell{mana_cost: 30, power_type: 0}, 5_000)

      assert entity.unit.power1 == 70
      assert entity.internal.last_mana_use_at == 5_000
      assert entity.internal.broadcast_update? == true
    end

    test "god mode skips mana costs" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 10, max_power1: 100},
        internal: %Internal{godmode: true}
      }

      entity = Resources.spend_power(entity, %Spell{mana_cost: 30, power_type: 0}, 5_000)

      assert entity.unit.power1 == 10
      assert entity.internal.last_mana_use_at == nil
      assert entity.internal.broadcast_update? == false
    end

    test "clamps power at zero" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 10, max_power1: 100},
        internal: %Internal{}
      }

      assert Resources.spend_power(entity, %Spell{mana_cost: 30, power_type: 0}, 5_000).unit.power1 == 0
    end

    test "deducts rage without recording mana use" do
      entity = Resources.spend_power(rage_user(rage: 300), %Spell{mana_cost: 150, power_type: 1}, 5_000)

      assert entity.unit.power2 == 150
      assert entity.internal.last_mana_use_at == nil
    end

    test "health costs come off health but never kill" do
      entity = %Mob{
        unit: %Unit{power_type: 1, health: 100, max_health: 100, base_health: 80},
        internal: %Internal{}
      }

      spell = %Spell{mana_cost: 0, mana_cost_percent: 20, power_type: -2}

      entity = Resources.spend_power(entity, spell, 5_000)

      assert entity.unit.health == 84
      assert entity.internal.broadcast_update? == true

      entity = %{entity | unit: %{entity.unit | health: 10}}

      assert Resources.spend_power(entity, spell, 5_000).unit.health == 1
    end

    test "god mode skips health costs" do
      entity = %Mob{
        unit: %Unit{power_type: 1, health: 100, max_health: 100, base_health: 80},
        internal: %Internal{godmode: true}
      }

      spell = %Spell{mana_cost: 0, mana_cost_percent: 20, power_type: -2}

      assert Resources.spend_power(entity, spell, 5_000) == entity
    end

    test "percent costs of a power draw from the maximum" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 100, max_power1: 100, base_mana: 80},
        internal: %Internal{}
      }

      entity = Resources.spend_power(entity, %Spell{mana_cost: 10, mana_cost_percent: 10, power_type: 0}, 5_000)

      assert entity.unit.power1 == 82
    end

    test "ignores spells without a cost" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 100, max_power1: 100},
        internal: %Internal{}
      }

      assert Resources.spend_power(entity, %Spell{mana_cost: 0, power_type: 0}, 5_000) == entity
    end
  end

  describe "refund_power/3" do
    test "returns a fraction of the spell cost" do
      entity = Resources.refund_power(rage_user(rage: 100), %Spell{mana_cost: 150, power_type: 1}, 0.82)

      assert entity.unit.power2 == 223
    end

    test "ignores non-positive fractions" do
      entity = rage_user(rage: 100)

      assert Resources.refund_power(entity, %Spell{mana_cost: 150, power_type: 1}, 0) == entity
    end
  end
end
