defmodule ThistleTea.Game.Core.Creature.SummonDespawnTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Creature.SummonDespawn

  @timed_or_dead 1
  @timed_or_corpse 2
  @timed 3
  @timed_out_of_combat 4
  @corpse 5
  @corpse_timed 6
  @dead 7
  @manual 8
  @timed_combat_or_dead 9
  @timed_combat_or_corpse 10
  @timed_death_and_dead 11

  describe "timer_at_spawn?/1" do
    test "times only the types whose timer runs while the summon lives" do
      assert Enum.filter(1..11, &SummonDespawn.timer_at_spawn?/1) ==
               [@timed_or_dead, @timed_or_corpse, @timed, @timed_out_of_combat] ++
                 [@timed_combat_or_dead, @timed_combat_or_corpse]
    end
  end

  describe "at_death/1" do
    test "removes the body of summons that vanish when they die" do
      for type <- [@timed_or_corpse, @corpse, @timed_combat_or_corpse],
          do: assert(SummonDespawn.at_death(type) == :despawn)
    end

    test "starts the timer over for summons timed from their death" do
      for type <- [@timed_out_of_combat, @corpse_timed], do: assert(SummonDespawn.at_death(type) == :restart_timer)
    end

    test "keeps a lootable corpse for every other type" do
      for type <- [@timed_or_dead, @timed, @dead, @manual, @timed_combat_or_dead, @timed_death_and_dead],
          do: assert(SummonDespawn.at_death(type) == :keep_corpse)
    end
  end

  describe "when_due/3" do
    test "a timed-or-dead corpse outlasts its timer" do
      assert SummonDespawn.when_due(@timed_or_dead, true, false) == :ignore
      assert SummonDespawn.when_due(@timed_or_dead, false, false) == :despawn
      assert SummonDespawn.when_due(@timed_or_dead, false, true) == :wait
    end

    test "timers that keep running after death end the corpse" do
      for type <- [@timed, @timed_out_of_combat, @corpse_timed, @timed_combat_or_dead],
          do: assert(SummonDespawn.when_due(type, true, false) == :despawn)
    end

    test "only out-of-combat types wait out a fight" do
      assert SummonDespawn.when_due(@timed_out_of_combat, false, true) == :wait
      assert SummonDespawn.when_due(@timed, false, true) == :despawn
      assert SummonDespawn.when_due(@timed_combat_or_dead, false, true) == :despawn
    end

    test "a corpse-timed summon ignores a timer while it lives" do
      assert SummonDespawn.when_due(@corpse_timed, false, false) == :ignore
      assert SummonDespawn.when_due(@dead, false, false) == :ignore
    end
  end
end
