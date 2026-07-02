defmodule ThistleTea.Game.Entity.Data.CreatureSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.CreatureSpell

  describe "build/1" do
    test "converts delays from seconds to milliseconds" do
      entry =
        CreatureSpell.build(
          slot(delay_initial_min: 3, delay_initial_max: 6, delay_repeat_min: 14, delay_repeat_max: 20)
        )

      assert entry.delay_initial_min_ms == 3_000
      assert entry.delay_initial_max_ms == 6_000
      assert entry.delay_repeat_min_ms == 14_000
      assert entry.delay_repeat_max_ms == 20_000
    end

    test "decodes cast flags into atoms" do
      entry = CreatureSpell.build(slot(cast_flags: 0x008 + 0x020 + 0x040))

      assert CreatureSpell.flag?(entry, :main_ranged)
      assert CreatureSpell.flag?(entry, :aura_not_present)
      assert CreatureSpell.flag?(entry, :only_in_melee)
      refute CreatureSpell.flag?(entry, :triggered)
    end

    test "decodes cast targets" do
      assert CreatureSpell.build(slot(cast_target: 0)).cast_target == :self
      assert CreatureSpell.build(slot(cast_target: 1)).cast_target == :victim
      assert CreatureSpell.build(slot(cast_target: 4)).cast_target == :hostile_random
      assert CreatureSpell.build(slot(cast_target: 17)).cast_target == :friendly_injured
      assert CreatureSpell.build(slot(cast_target: 19)).cast_target == :friendly_missing_buff
      assert CreatureSpell.build(slot(cast_target: 22)).cast_target == 22
    end

    test "normalizes out-of-range probability to 100" do
      assert CreatureSpell.build(slot(probability: 0)).probability == 100
      assert CreatureSpell.build(slot(probability: 150)).probability == 100
      assert CreatureSpell.build(slot(probability: 25)).probability == 25
    end

    test "returns nil without a spell id" do
      assert CreatureSpell.build(slot(spell_id: 0)) == nil
      assert CreatureSpell.build(nil) == nil
    end
  end

  describe "roll_initial_delay_ms/1" do
    test "stays within the configured window" do
      entry = CreatureSpell.build(slot(delay_initial_min: 2, delay_initial_max: 4))

      for _ <- 1..50 do
        delay = CreatureSpell.roll_initial_delay_ms(entry)
        assert delay >= 2_000 and delay <= 4_000
      end
    end

    test "is exact for a fixed window" do
      entry = CreatureSpell.build(slot(delay_repeat_min: 2, delay_repeat_max: 2))

      assert CreatureSpell.roll_repeat_delay_ms(entry) == 2_000
    end
  end

  defp slot(overrides) do
    Map.merge(
      %{
        spell_id: 20_793,
        probability: 100,
        cast_target: 1,
        target_param1: 0,
        target_param2: 0,
        cast_flags: 0,
        delay_initial_min: 0,
        delay_initial_max: 0,
        delay_repeat_min: 0,
        delay_repeat_max: 0
      },
      Map.new(overrides)
    )
  end
end
