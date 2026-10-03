defmodule ThistleTea.Game.World.Loader.Mob.SpawnFlagsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder
  alias ThistleTea.Test.Unique

  describe "Mangos.Creature.held_back?/1" do
    test "holds back disabled and invisible spawns" do
      for {flags, held_back?} <- [{0, false}, {0x01, false}, {0x02, true}, {0x40, true}, {0x80, false}, {0x42, true}] do
        assert Mangos.Creature.held_back?(%Mangos.Creature{spawn_flags: flags}) == held_back?
      end
    end
  end

  describe "Mangos.Creature.dead?/1" do
    test "spawns dead with the dead flag or no health" do
      assert Mangos.Creature.dead?(%Mangos.Creature{spawn_flags: 0x80})
      assert Mangos.Creature.dead?(%Mangos.Creature{health_percent: 0.0})
      refute Mangos.Creature.dead?(%Mangos.Creature{spawn_flags: 0x02})
    end
  end

  describe "build/1" do
    test "a spawn that is dead by default builds as a settled corpse" do
      corpse = build(0x80)
      assert corpse.unit.health == 0
      assert corpse.internal.death_finalized?
      assert corpse.internal.spawn.dead?

      living = build(0)
      assert living.unit.health == living.unit.max_health
      refute living.internal.death_finalized?
    end
  end

  describe "Mob.respawn/2" do
    test "a spawn that is dead by default respawns dead unless revived" do
      corpse = build(0x80)

      assert %Mob{unit: %{health: 0}, internal: %{death_finalized?: true}} = Mob.respawn(corpse)

      revived = Mob.respawn(corpse, revive?: true)
      assert revived.unit.health == revived.unit.max_health
      refute revived.internal.death_finalized?
      assert revived.internal.spawn.dead?
    end
  end

  defp build(spawn_flags) do
    entry = Unique.integer()

    %Mangos.Creature{
      guid: Unique.integer(),
      id: entry,
      modelid: 100,
      curhealth: 400,
      curmana: 0,
      selected_level: 10,
      spawn_flags: spawn_flags,
      creature_movement: [],
      creature_template: %Mangos.CreatureTemplate{
        entry: entry,
        name: "Fallen Paladin",
        min_level: 10,
        max_level: 10,
        faction_alliance: 35,
        melee_base_attack_time: 2_000,
        speed_run: 1.0,
        min_melee_dmg: 10.0,
        max_melee_dmg: 20.0
      }
    }
    |> MobBuilder.build()
  end
end
