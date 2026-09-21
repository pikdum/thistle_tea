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

  describe "forget/3 and restore/2" do
    test "retains learned weapon values and restores only newly available skills" do
      axe = %{value: 240, max: 250, range: :level, always_max?: false}
      mace = %{axe | value: 190}
      {known, forgotten} = Skills.forget(%{172 => axe, 160 => mace}, [172], %{})
      assert known == %{160 => mace}
      assert forgotten == %{172 => axe}
      assert Skills.restore(known, forgotten) == {known, forgotten}
      assert {restored, %{}} = Skills.restore(%{172 => Skills.new_entry(:level, false, 60)}, forgotten)
      assert restored[172].value == 240
      assert restored[172].max == 300
      assert {capped, %{}} = Skills.restore(%{172 => Skills.new_entry(:level, false, 40)}, forgotten)
      assert capped[172].value == 200
    end
  end

  describe "ranged_weapon_skill/2" do
    test "reads weapon skills independently of permanent and temporary enchants" do
      packed = 100 + Bitwise.bsl(1900, 32) + Bitwise.bsl(263, 64)
      player = %{visible_item_16_0: packed, visible_item_17_0: packed, visible_item_18_0: packed}
      get_template = fn 100 -> %{class: 2, subclass: 7} end

      assert Skills.main_hand_weapon_skill(player, get_template) == 43
      assert Skills.off_hand_weapon_skill(player, get_template) == 43
      assert Skills.ranged_weapon_skill(player, get_template) == 43
    end

    test "uses the equipped ranged weapon subclass" do
      player = %{visible_item_18_0: 100}
      get_template = fn 100 -> %{class: 2, subclass: 2} end

      assert Skills.ranged_weapon_skill(player, get_template) == 45
    end

    test "returns nil without a ranged weapon" do
      assert Skills.ranged_weapon_skill(%{visible_item_18_0: 0}, fn _ -> nil end) == nil
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
    test "encodes signed skill modifiers separately from learned progress" do
      skills = %{95 => %{value: 250, max: 250}}

      assert <<95::little-size(32), 250::little-size(16), 250::little-size(16), -5::little-signed-size(16),
               3::little-signed-size(16), _rest::binary>> =
               Skills.encode(skills, %{95 => {-5, 3}})
    end

    test "packs id, value, and max into 128 twelve-byte slots" do
      skills = %{43 => Skills.new_entry(:level, false, 2)}

      assert <<43::little-size(32), 1::little-size(16), 10::little-size(16), 0::size(32), rest::binary>> =
               Skills.encode(skills)

      assert byte_size(rest) == 127 * 12
      assert rest == <<0::size(127 * 12 * 8)>>
    end

    test "clears an empty skill block and omits missing skills" do
      assert Skills.encode(%{}) == :binary.copy(<<0>>, 128 * 12)
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
    test "keeps existing slots stable when a lower-numbered skill is learned or abandoned" do
      original = Skills.learn_rank(%{}, 333, 75)
      added = Skills.learn_rank(original, 186, 75)
      assert added[333].slot == 0
      assert added[186].slot == 1
      assert binary_part(Skills.encode(added), 0, 12) == binary_part(Skills.encode(original), 0, 12)
      removed = Map.delete(added, 333)
      assert binary_part(Skills.encode(removed), 0, 12) == <<0::size(96)>>
      assert binary_part(Skills.encode(removed), 12, 12) == binary_part(Skills.encode(added), 12, 12)
      relearned = Skills.learn_rank(removed, 333, 75)
      assert relearned[333].slot == 0
      assert relearned[186].slot == 1
    end

    test "learns apprentice fishing and raises later rank caps without resetting progress" do
      skills = Skills.learn_rank(%{}, Skills.fishing_skill(), 75)
      assert skills[356] == %{value: 1, max: 75, range: :tier, always_max?: false, step: 1, slot: 0}

      skills = Map.update!(skills, 356, &%{&1 | value: 50})
      assert Skills.learn_rank(skills, 356, 150)[356].value == 50
      assert Skills.learn_rank(skills, 356, 150)[356].max == 150
      assert Skills.learn_rank(skills, 356, 150)[356].step == 2
    end

    test "encodes trained tiers separately from skill value and maximum" do
      skills = %{} |> Skills.learn_rank(186, 150) |> Skills.max_professions()

      assert <<186::little-size(16), 2::little-size(16), 300::little-size(16), 300::little-size(16), _rest::binary>> =
               Skills.encode(skills)

      assert Skills.rank_known?(skills, 186, 75)
      assert Skills.rank_known?(skills, 186, 150)
      refute Skills.rank_known?(skills, 186, 225)
    end
  end

  describe "merge/2" do
    test "preserves current values and slots while assigning unused slots to derived skills" do
      known = Skills.learn_rank(%{}, 186, 75)

      derived =
        Skills.with_slots(%{43 => Skills.new_entry(:level, false, 60), 95 => Skills.new_entry(:level, false, 60)})

      merged = Skills.merge(known, derived)
      assert merged[186] == known[186]
      assert merged[43].slot == 1
      assert merged[95].slot == 2
      assert Skills.merge(merged, derived) == merged
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
