defmodule ThistleTea.Game.Spell.AreaTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Entity.Logic.QuestLog.Entry
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.Area.Context
  alias ThistleTea.Game.Spell.Requirements

  describe "matches?/2" do
    setup [:player_context]

    test "matches zones and subareas without requiring a player", %{context: context} do
      assert Area.matches?(%Area{area_id: 139}, context)
      assert Area.matches?(%Area{area_id: 2268}, context)
      assert Area.matches?(%Area{}, %Context{})
      refute Area.matches?(%Area{area_id: 148}, context)
      refute Area.matches?(%Area{area_id: 148}, nil)
    end

    test "combines race, gender, and signed aura requirements", %{context: context} do
      rule = %Area{race_mask: 1, gender: 1, aura_spell: 30_238}
      assert Area.matches?(rule, context)
      refute Area.matches?(%{rule | race_mask: 2}, context)
      refute Area.matches?(%{rule | gender: 0}, context)
      refute Area.matches?(%{rule | aura_spell: -30_238}, context)
      assert Area.matches?(%{rule | aura_spell: -123}, context)
      refute Area.matches?(%{rule | aura_spell: 123}, context)
    end

    test "requires a player even for a negative aura requirement" do
      for rule <- [
            %Area{race_mask: 1},
            %Area{gender: 0},
            %Area{aura_spell: -1},
            %Area{quest_start: 1},
            %Area{quest_end: 1}
          ] do
        refute Area.matches?(rule, %Context{})
      end
    end

    test "distinguishes active and rewarded start quests", %{context: context} do
      refute Area.matches?(%Area{quest_start: 10}, context)
      assert Area.matches?(%Area{quest_start: 10, quest_start_active?: true}, context)
      assert Area.matches?(%Area{quest_start: 20}, context)
      refute Area.matches?(%Area{quest_start: 30, quest_start_active?: true}, context)
    end

    test "ends on quest reward and allows an active start and end quest", %{context: context} do
      assert Area.matches?(%Area{quest_end: 10}, context)
      refute Area.matches?(%Area{quest_end: 20}, context)
      assert Area.matches?(%Area{quest_start: 10, quest_end: 10, quest_start_active?: true}, context)
    end
  end

  describe "validate/2" do
    setup [:player_context]

    test "accepts any complete alternative and leaves unrestricted spells alone", %{context: context} do
      spell = %Spell{area_rules: [%Area{area_id: 148}, %Area{area_id: 139, gender: 1}]}
      assert Area.validate(spell, context) == :ok
      assert Area.validate(%Spell{}, nil) == :ok
      assert Area.validate(spell, %Context{zone_id: 139}) == {:error, :requires_area}
      assert Area.required_area(spell) == 148
      assert Area.required_area(%Spell{}) == 0
    end

    test "rechecks location when the cast reaches launch", %{context: context} do
      spell = %Spell{area_rules: [%Area{area_id: 139}]}
      assert Requirements.required?(nil, spell)
      assert Requirements.validate(nil, spell, %Requirements{spell_area: context}) == :ok

      assert Requirements.validate(nil, spell, %Requirements{spell_area: %Context{zone_id: 148}}) ==
               {:error, :requires_area}
    end
  end

  defp player_context(_context) do
    player = %Subject{
      kind: :player,
      race: 1,
      gender: 1,
      aura_ids: MapSet.new([30_238]),
      quest_log: %{0 => %Entry{quest_id: 10}},
      rewarded_quests: MapSet.new([20])
    }

    %{context: %Context{zone_id: 139, area_id: 2268, player: player}}
  end
end
