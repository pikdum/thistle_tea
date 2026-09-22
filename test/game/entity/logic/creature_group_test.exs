defmodule ThistleTea.Game.Entity.Logic.CreatureGroupTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.CreatureGroup
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member

  setup [:actors]

  describe "actions/4" do
    test "aggregates follower options and excludes dead, absent, and engaged allies", %{actors: actors} do
      group = group(2)
      actors = actors |> put_in([2, :combat?], true) |> put_in([3, :alive?], false)
      assert CreatureGroup.actions(group, 2, {:attack, 99}, actors) == [{1, {:attack, 99}}]
      assert CreatureGroup.actions(group(0), 2, {:attack, 99}, actors) == []
      assert CreatureGroup.actions(group, 2, {:attack, 99}, put_in(actors[1].present?, false)) == []
    end

    test "evades living fighters and revives dead members on master evade", %{actors: actors} do
      actors = actors |> put_in([1, :combat?], true) |> put_in([3, :alive?], false)
      assert CreatureGroup.actions(group(0x14), 2, :evade, actors) == [{1, :evade}, {3, :respawn}]
      assert CreatureGroup.actions(group(0x10), 2, :evade, actors) == []
      assert CreatureGroup.actions(group(0x10), 1, :evade, actors) == [{3, :respawn}]
      assert CreatureGroup.actions(group(0x20), 2, :evade, actors) == [{3, :respawn}]
    end

    test "respawns only dead present companions", %{actors: actors} do
      actors = actors |> put_in([1, :alive?], false) |> put_in([3, :alive?], false) |> put_in([3, :present?], false)
      assert CreatureGroup.actions(group(8), 2, :respawn, actors) == [{1, :respawn}]
      assert CreatureGroup.actions(group(0), 2, :respawn, actors) == []
    end

    test "death notifications select the leader and followers independently", %{actors: actors} do
      assert CreatureGroup.actions(group(0x40), 2, :death, actors) == [{1, {:member_died, 2, false}}]

      assert CreatureGroup.actions(group(0x80), 1, :death, actors) == [
               {2, {:member_died, 1, true}},
               {3, {:member_died, 1, true}}
             ]

      assert CreatureGroup.actions(group(0x80), 2, :death, actors) == [{3, {:member_died, 2, false}}]

      assert CreatureGroup.actions(group(0xC0), 2, :death, put_in(actors[1].alive?, false)) == [
               {3, {:member_died, 2, false}}
             ]
    end
  end

  describe "dead?/3" do
    test "excludes the evaluating member and absent creatures", %{actors: actors} do
      actors = actors |> put_in([2, :alive?], false) |> put_in([3, :present?], false)
      assert CreatureGroup.dead?(group(0), 1, actors)
      refute CreatureGroup.dead?(group(0), 2, actors)
    end
  end

  describe "add/3" do
    test "ignores the leader row and retains accumulated options after member removal" do
      group = CreatureGroup.new(1) |> CreatureGroup.add(1, %Member{flags: 255})
      assert group.flags == 0
      assert group.members == %{}
      group = group |> CreatureGroup.add(2, %Member{flags: 2}) |> CreatureGroup.remove(2)
      assert group.flags == 2
      assert CreatureGroup.member_ids(group) == [1]
    end
  end

  defp actors(_context) do
    %{actors: Map.new(1..3, &{&1, %{alive?: true, combat?: false, present?: true}})}
  end

  defp group(flags) do
    CreatureGroup.new(1)
    |> CreatureGroup.add(2, %Member{flags: flags})
    |> CreatureGroup.add(3, %Member{})
  end
end
