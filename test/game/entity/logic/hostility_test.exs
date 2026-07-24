defmodule ThistleTea.Game.Entity.Logic.HostilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid

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

  describe "valid_attack_target?/2" do
    test "allows players to attack neutral creature factions without reputation" do
      player = player(alliance())
      target = mob(wolf(), faction_can_have_reputation?: false)

      refute Hostility.valid_hostile_target?(player, target)
      assert Hostility.valid_attack_target?(player, target)
    end

    test "does not allow players to attack friendly neutral targets" do
      player = player(alliance())
      target = mob(friendly(), faction_can_have_reputation?: false)

      refute Hostility.valid_attack_target?(player, target)
    end

    test "does not allow neutral player creature attacks when the creature faction has reputation" do
      player = player(alliance())
      target = mob(wolf(), faction_can_have_reputation?: true)

      refute Hostility.valid_attack_target?(player, target)
    end

    test "does not allow neutral creature versus creature attacks" do
      refute Hostility.valid_attack_target?(mob(wolf()), mob(neutral_creature()))
    end

    test "does not allow attacks against aura-unattackable targets" do
      target = mob(defias()) |> Map.put(:unit_flags, 0x00010000)

      refute Hostility.valid_attack_target?(player(alliance()), target)
    end

    test "allows player-controlled pets to attack neutral creatures" do
      owner_guid = Guid.from_low_guid(:player, 1)
      pet = mob(alliance()) |> Map.put(:owner_guid, owner_guid)
      target = mob(wolf(), faction_can_have_reputation?: false)

      assert Hostility.valid_attack_target?(pet, target)
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

  defp friendly do
    %FactionTemplate{id: 35, faction: 31, flags: 0, faction_group: 0, friend_group: 1, enemy_group: 0, friends_0: 31}
  end

  defp player(faction_template) do
    %{
      object: %{guid: Guid.from_low_guid(:player, 1)},
      faction_template: faction_template,
      unit_flags: 0,
      alive?: true
    }
  end

  defp mob(faction_template, opts \\ []) do
    %{
      guid: Guid.from_low_guid(:mob, faction_template.id || 1, System.unique_integer([:positive])),
      faction_template: faction_template,
      faction_can_have_reputation?: Keyword.get(opts, :faction_can_have_reputation?, false),
      unit_flags: 0,
      alive?: true
    }
  end
end
