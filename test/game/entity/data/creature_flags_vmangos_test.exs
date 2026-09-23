defmodule ThistleTea.Game.Entity.Data.CreatureFlagsVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.CreatureFlags
  alias ThistleTea.Game.Entity.Logic.MovementStats
  alias ThistleTea.Game.Entity.Logic.Skills

  @moduletag :vmangos_db

  describe "Mob.build/1" do
    test "retains raid-binding boss flags independently of elite rank" do
      assert CreatureFlags.locks_raid?(build(10_184))
      assert CreatureFlags.locks_raid?(build(11_982))
      refute CreatureFlags.locks_raid?(build(1853))
    end

    test "loads the separate wounded slowdown exemption" do
      boss = build(1853)
      assert boss.internal.creature.rank == 1
      assert CreatureFlags.no_wounded_slowdown?(boss)
      wounded = %{boss | unit: %{boss.unit | health: 1, max_health: 1_000}}
      assert MovementStats.recompute(wounded).movement_block.run_speed == boss.movement_block.base_run_speed
      refute CreatureFlags.no_wounded_slowdown?(build(1921))
    end

    test "combat dummies retain their distinct player immunity" do
      for entry <- [1921, 4952, 5652] do
        mob = build(entry)
        assert mob.internal.invincibility_health_threshold == 1
        refute Blackboard.melee_enabled?(Blackboard.new(), mob)
        refute Blackboard.combat_movement?(Blackboard.new(), mob)
        assert CreatureFlags.has?(mob, :immune_to_player) == (entry != 1921)
        assert Bitwise.band(mob.unit.flags, 0x100) != 0 == (entry != 1921)
      end
    end

    test "water guardians have no defense and repair bots are sessile" do
      guardian = build(3950)
      assert Skills.defense_value(guardian) == 0
      assert CreatureFlags.has?(guardian, :no_spell_defense)
      bot = build(14_337)
      refute Blackboard.combat_movement?(Blackboard.new(), bot)
      assert Blackboard.melee_enabled?(Blackboard.new(), bot)
    end
  end

  defp build(entry) do
    template = Mangos.Repo.get!(Mangos.CreatureTemplate, entry)

    Mob.build(%Mangos.Creature{
      guid: 1,
      id: entry,
      modelid: template.model_id1,
      curhealth: 100,
      equip_items: [nil, nil, nil],
      creature_movement: [],
      creature_template: template
    })
  end
end
