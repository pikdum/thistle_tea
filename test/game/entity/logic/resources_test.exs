defmodule ThistleTea.Game.Entity.Logic.ResourcesTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Resources

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
end
