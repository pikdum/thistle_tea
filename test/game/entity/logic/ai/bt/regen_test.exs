defmodule ThistleTea.Game.Entity.Logic.AI.BT.RegenTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Regen

  describe "initialize/3" do
    test "revived pets wait full resource intervals before regenerating" do
      pet = %Mob{
        unit: %Unit{health: 45, max_health: 300, power_type: 2, power3: 10, max_power3: 100},
        internal: %Internal{creature: %Creature{regenerate_stats: 3}, pet: %Pet{kind: :hunter}}
      }

      blackboard = Regen.initialize(pet, Blackboard.new(), 1_000)
      assert {:failure, waiting, blackboard} = Regen.tick(pet, blackboard, 1_000)
      assert waiting.unit.health == 45
      assert waiting.unit.power3 == 10
      assert {:failure, focused, blackboard} = Regen.tick(waiting, blackboard, 5_000)
      assert focused.unit.health == 45
      assert focused.unit.power3 == 35
      assert {:failure, healed, _blackboard} = Regen.tick(focused, blackboard, 6_000)
      assert healed.unit.health == 145
    end
  end

  test "ticks hunter pet focus and creature resources on independent clocks" do
    pet = %Mob{
      unit: %Unit{health: 50, max_health: 300, power_type: 2, power3: 10, max_power3: 100},
      internal: %Internal{
        creature: %Creature{regenerate_stats: 3},
        pet: %Pet{kind: :hunter}
      }
    }

    assert {:failure, pet, blackboard} = Regen.tick(pet, Blackboard.new(), 1_000)
    assert pet.unit.health == 150
    assert pet.unit.power3 == 35
    assert blackboard.maintenance.next_regen_at == 6_000
    assert blackboard.maintenance.next_focus_regen_at == 5_000

    assert {:failure, pet, blackboard} = Regen.tick(pet, blackboard, 5_000)
    assert pet.unit.health == 150
    assert pet.unit.power3 == 60

    assert {:failure, pet, _blackboard} = Regen.tick(pet, blackboard, 6_000)
    assert pet.unit.health == 250
    assert pet.unit.power3 == 60
  end
end
