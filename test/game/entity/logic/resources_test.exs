defmodule ThistleTea.Game.Entity.Logic.ResourcesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Spell

  describe "gain_rage/2" do
    test "adds rage up to the rage cap" do
      entity = %Mob{
        unit: %Unit{power_type: 1, power2: 950, max_power2: 1_000},
        internal: %Internal{}
      }

      entity = Resources.gain_rage(entity, 100)

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

  describe "gain_outgoing_auto_attack_rage/2" do
    test "converts outgoing auto attack damage into rage" do
      entity = %Mob{
        unit: %Unit{power_type: 1, power2: 0, max_power2: 1_000},
        internal: %Internal{}
      }

      entity = Resources.gain_outgoing_auto_attack_rage(entity, %{damage: 12})

      assert entity.unit.power2 == 120
      assert entity.internal.broadcast_update? == true
    end

    test "does not generate rage for queued melee spells" do
      entity = %Mob{
        unit: %Unit{power_type: 1, power2: 0, max_power2: 1_000},
        internal: %Internal{}
      }

      assert Resources.gain_outgoing_auto_attack_rage(entity, %{damage: 12, queued_spell_id: 78}) == entity
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

    test "clamps power at zero" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 10, max_power1: 100},
        internal: %Internal{}
      }

      assert Resources.spend_power(entity, %Spell{mana_cost: 30, power_type: 0}, 5_000).unit.power1 == 0
    end

    test "deducts rage without recording mana use" do
      entity = %Mob{
        unit: %Unit{power_type: 1, power2: 300, max_power2: 1_000},
        internal: %Internal{}
      }

      entity = Resources.spend_power(entity, %Spell{mana_cost: 150, power_type: 1}, 5_000)

      assert entity.unit.power2 == 150
      assert entity.internal.last_mana_use_at == nil
    end

    test "ignores spells without a cost" do
      entity = %Mob{
        unit: %Unit{power_type: 0, power1: 100, max_power1: 100},
        internal: %Internal{}
      }

      assert Resources.spend_power(entity, %Spell{mana_cost: 0, power_type: 0}, 5_000) == entity
    end
  end
end
