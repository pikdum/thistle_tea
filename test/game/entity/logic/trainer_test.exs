defmodule ThistleTea.Game.Entity.Logic.TrainerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Logic.Trainer

  @fireball_rank_2 %TrainerSpell{
    teach_spell_id: 5145,
    learned_spell_id: 143,
    cost: 200,
    req_level: 6,
    prev_spell_id: 133
  }

  describe "state/3" do
    test "treats a superseded profession rank as known without downgrading or charging again" do
      skills = %{} |> Skills.learn_rank(186, 150) |> Skills.learn_rank(182, 75)
      apprentice = %TrainerSpell{learned_spell_id: 2575, skill_id: 186, skill_max: 75}
      assert Trainer.state(apprentice, [2576], 60, skills) == :gray
    end

    test "disables a third primary profession but permits upgrades and secondary skills" do
      skills = %{} |> Skills.learn_rank(186, 75) |> Skills.learn_rank(182, 75)
      first_rank = %TrainerSpell{skill_id: 171, skill_max: 75, learned_spell_id: 2259}
      assert Trainer.state(first_rank, [], 60, skills) == :green_disabled
      assert Trainer.state(%{first_rank | skill_id: 185}, [], 60, skills) == :green
      assert Trainer.state(%{first_rank | skill_id: 186, skill_max: 150}, [], 60, skills) == :green
      assert Trainer.state(first_rank, [2259], 60, skills) == :gray
      assert Trainer.state(first_rank, [], 60, Map.delete(skills, 186)) == :green
    end

    test "projects free slots from known primary skills" do
      skills = %{} |> Skills.learn_rank(186, 75) |> Skills.learn_rank(185, 75)
      assert Player.profession_points(%{skills: skills}) == <<1::little-size(32)>>
      assert Player.profession_points(%{skills: %{}}) == <<2::little-size(32)>>
    end

    test "gray when the spell is already known" do
      assert Trainer.state(@fireball_rank_2, [143], 60) == :gray
    end

    test "red when below the required level" do
      assert Trainer.state(@fireball_rank_2, [133], 5) == :red
    end

    test "red when the previous rank is not known" do
      assert Trainer.state(@fireball_rank_2, [], 6) == :red
    end

    test "red when the required spell is not known" do
      spell = %{@fireball_rank_2 | prev_spell_id: nil, req_spell_id: 5143}
      assert Trainer.state(spell, [133], 6) == :red
    end

    test "red when a skill is required" do
      spell = %{@fireball_rank_2 | req_skill: 171, req_skill_value: 50}
      assert Trainer.state(spell, [133], 6) == :red
    end

    test "green when the required skill rank is met" do
      spell = %{@fireball_rank_2 | req_skill: 356, req_skill_value: 50}
      skills = %{356 => %{value: 50, max: 75, range: :level, always_max?: false}}
      assert Trainer.state(spell, [133], 6, skills) == :green
    end

    test "green when all requirements are met" do
      assert Trainer.state(@fireball_rank_2, [133], 6) == :green
    end

    test "treats nil known spells as none" do
      assert Trainer.state(%TrainerSpell{learned_spell_id: 143}, nil, 1) == :green
    end
  end

  describe "fits_class_race?/3" do
    @mage 8
    @warrior 1
    @human 1
    @orc 2

    test "fits everyone without skill line masks" do
      assert Trainer.fits_class_race?(%TrainerSpell{}, @warrior, @orc)
    end

    test "matches the class mask" do
      spell = %TrainerSpell{class_race_masks: [{0x80, 0}]}
      assert Trainer.fits_class_race?(spell, @mage, @human)
      refute Trainer.fits_class_race?(spell, @warrior, @human)
    end

    test "matches the race mask" do
      spell = %TrainerSpell{class_race_masks: [{0, 0x01}]}
      assert Trainer.fits_class_race?(spell, @mage, @human)
      refute Trainer.fits_class_race?(spell, @mage, @orc)
    end

    test "fits when any mask pair matches" do
      spell = %TrainerSpell{class_race_masks: [{0x01, 0}, {0x80, 0}]}
      assert Trainer.fits_class_race?(spell, @mage, @human)
      assert Trainer.fits_class_race?(spell, @warrior, @orc)
    end
  end
end
