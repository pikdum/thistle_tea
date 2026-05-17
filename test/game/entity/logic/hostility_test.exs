defmodule ThistleTea.Game.Entity.Logic.HostilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Hostility

  describe "hostile?/2" do
    test "uses faction template enemy masks" do
      assert Hostility.hostile?(defias(), alliance())
      refute Hostility.hostile?(wolf(), alliance())
    end

    test "honors explicit friend factions before masks" do
      assert FactionTemplate.friendly_to?(friendly_defias(), defias())
      refute FactionTemplate.hostile_to?(friendly_defias(), defias())
    end
  end

  describe "can_initiate_attack?/1" do
    test "returns false for neutral factions" do
      refute Hostility.can_initiate_attack?(%{faction_template: neutral_creature()})
    end

    test "returns false for non-attackable units" do
      refute Hostility.can_initiate_attack?(%{faction_template: defias(), unit_flags: 0x00000002})
    end
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp defias do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp friendly_defias do
    %FactionTemplate{id: 99, faction: 99, flags: 0, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end

  defp neutral_creature do
    %FactionTemplate{id: 7, faction: 7, flags: 0, faction_group: 0, friend_group: 0, enemy_group: 0}
  end
end
