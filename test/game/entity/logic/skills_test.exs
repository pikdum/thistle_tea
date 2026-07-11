defmodule ThistleTea.Game.Entity.Logic.SkillsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Skills

  defp always_gain(_chance), do: true
  defp never_gain(_chance), do: false

  describe "new_entry/3" do
    test "builds entries per range" do
      assert Skills.new_entry(:level, false, 10) == %{value: 1, max: 50, range: :level, always_max?: false}
      assert Skills.new_entry(:level, true, 10) == %{value: 50, max: 50, range: :level, always_max?: true}
      assert Skills.new_entry(:mono, false, 10) == %{value: 1, max: 1, range: :mono, always_max?: false}
      assert Skills.new_entry(:language, false, 10) == %{value: 300, max: 300, range: :language, always_max?: false}
    end
  end

  describe "on_level_up/2" do
    test "raises maxes for level skills and keeps values" do
      skills = %{
        43 => Skills.new_entry(:level, false, 1),
        8 => Skills.new_entry(:level, true, 1),
        98 => Skills.new_entry(:language, false, 1)
      }

      leveled = Skills.on_level_up(skills, 2)

      assert leveled[43] == %{value: 1, max: 10, range: :level, always_max?: false}
      assert leveled[8] == %{value: 10, max: 10, range: :level, always_max?: true}
      assert leveled[98].value == 300
    end
  end

  describe "max_out/1" do
    test "raises level skill values to their max and leaves other ranges alone" do
      skills = %{
        43 => Skills.new_entry(:level, false, 50),
        162 => Skills.new_entry(:mono, false, 50),
        98 => Skills.new_entry(:language, false, 50)
      }

      maxed = Skills.max_out(skills)

      assert maxed[43] == %{value: 250, max: 250, range: :level, always_max?: false}
      assert maxed[162].value == 1
      assert maxed[98].value == 300
    end
  end

  describe "max_professions/2" do
    test "raises known tier skills to the requested cap only" do
      skills = %{
        356 => %{value: 75, max: 150, range: :tier, always_max?: false},
        43 => Skills.new_entry(:level, false, 60)
      }

      maxed = Skills.max_professions(skills)

      assert maxed[356] == %{value: 300, max: 300, range: :tier, always_max?: false}
      assert maxed[43] == skills[43]
    end
  end

  describe "encode/1" do
    test "packs id, value, and max into 128 twelve-byte slots" do
      skills = %{43 => Skills.new_entry(:level, false, 2)}

      assert <<43::little-size(32), 1::little-size(16), 10::little-size(16), 0::size(32), rest::binary>> =
               Skills.encode(skills)

      assert byte_size(rest) == 127 * 12
      assert rest == <<0::size(127 * 12 * 8)>>
    end

    test "returns nil for empty or missing skills" do
      assert Skills.encode(%{}) == nil
      assert Skills.encode(nil) == nil
    end
  end

  describe "combat_skill_up/3" do
    test "gains a weapon skill point when the roll succeeds" do
      skills = %{43 => Skills.new_entry(:level, false, 10)}
      opts = [player_level: 10, intellect: 20, roll: &always_gain/1]

      assert {:gained, gained} = Skills.combat_skill_up(skills, 43, opts)
      assert gained[43].value == 2
    end

    test "does not gain when the roll fails" do
      skills = %{43 => Skills.new_entry(:level, false, 10)}

      assert Skills.combat_skill_up(skills, 43, player_level: 10, roll: &never_gain/1) == :unchanged
    end

    test "does not gain past the level cap" do
      skills = %{43 => %{value: 50, max: 50, range: :level, always_max?: false}}

      assert Skills.combat_skill_up(skills, 43, player_level: 10, roll: &always_gain/1) == :unchanged
    end

    test "never gains on always-max, language, or unknown skills" do
      skills = %{
        8 => Skills.new_entry(:level, true, 10),
        98 => Skills.new_entry(:language, false, 10)
      }

      assert Skills.combat_skill_up(skills, 8, player_level: 10, roll: &always_gain/1) == :unchanged
      assert Skills.combat_skill_up(skills, 98, player_level: 10, roll: &always_gain/1) == :unchanged
      assert Skills.combat_skill_up(skills, 999, player_level: 10, roll: &always_gain/1) == :unchanged
    end

    test "defense gains scale with mob level and remaining skill" do
      skills = %{95 => Skills.new_entry(:level, false, 10)}

      chance_probe = fn chance ->
        send(self(), {:chance, chance})
        true
      end

      opts = [player_level: 10, mob_level: 11, defense?: true, roll: chance_probe]

      assert {:gained, gained} = Skills.combat_skill_up(skills, 95, opts)
      assert gained[95].value == 2
      assert_received {:chance, chance}
      assert chance > 0
    end
  end

  describe "learn_rank/3" do
    test "learns apprentice fishing and raises later rank caps without resetting progress" do
      skills = Skills.learn_rank(%{}, Skills.fishing_skill(), 75)
      assert skills[356] == %{value: 1, max: 75, range: :tier, always_max?: false}

      skills = Map.update!(skills, 356, &%{&1 | value: 50})
      assert Skills.learn_rank(skills, 356, 150)[356].value == 50
      assert Skills.learn_rank(skills, 356, 150)[356].max == 150
    end
  end

  describe "fishing_skill_up/2" do
    test "uses the VMangos fishing curve and respects the trained cap" do
      skills = %{356 => %{value: 75, max: 150, range: :level, always_max?: false}}

      probe = fn chance ->
        send(self(), {:chance, chance})
        true
      end

      assert {:gained, gained} = Skills.fishing_skill_up(skills, roll: probe)
      assert gained[356].value == 76
      assert_received {:chance, 100.0}

      capped = %{356 => %{value: 150, max: 150, range: :level, always_max?: false}}
      assert Skills.fishing_skill_up(capped, roll: &always_gain/1) == :unchanged
    end
  end

  describe "weapon_skill_for_subclass/1" do
    test "maps weapon subclasses to skill lines" do
      assert Skills.weapon_skill_for_subclass(7) == 43
      assert Skills.weapon_skill_for_subclass(10) == 136
      assert Skills.weapon_skill_for_subclass(15) == 173
      assert Skills.weapon_skill_for_subclass(14) == nil
    end
  end
end
