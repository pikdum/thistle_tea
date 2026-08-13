defmodule ThistleTea.Game.Entity.Logic.HostilityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem

  describe "hostile?/2" do
    test "uses faction template enemy masks" do
      assert Hostility.hostile?(defias(), alliance())
      refute Hostility.hostile?(wolf(), alliance())
    end

    test "treats duel opponents as hostile when target metadata carries a guid" do
      {caster, target_metadata} = start_duel()

      assert Hostility.hostile?(caster, target_metadata)
      refute Hostility.friendly?(caster, target_metadata)
    end

    test "same-faction players without a duel stay friendly" do
      caster = player(alliance())
      target = player(alliance(), 2) |> Map.delete(:object) |> Map.put(:guid, Guid.from_low_guid(:player, 2))

      refute Hostility.hostile?(caster, target)
      assert Hostility.friendly?(caster, target)
    end

    test "honors explicit friend factions before masks" do
      assert FactionTemplate.friendly_to?(friendly_defias(), defias())
      refute FactionTemplate.hostile_to?(friendly_defias(), defias())
    end

    test "uses at-war for player reactions to reputation factions" do
      player = player(alliance(), 1, %{29 => %{rank: :neutral, at_war?: true}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.hostile?(player, creature)
      refute Hostility.hostile?(creature, player)
      refute Hostility.friendly?(player, creature)
    end

    test "uses standing rank for creature reactions to players" do
      hostile_player = player(alliance(), 1, %{29 => %{rank: :hostile, at_war?: true}})
      honored_player = player(alliance(), 2, %{29 => %{rank: :honored, at_war?: false}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.hostile?(creature, hostile_player)
      assert Hostility.friendly?(creature, honored_player)
    end

    test "caps friendly standing at neutral for an at-war creature reaction" do
      player = player(alliance(), 1, %{29 => %{rank: :honored, at_war?: true}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      refute Hostility.hostile?(creature, player)
      refute Hostility.friendly?(creature, player)
      assert Hostility.hostile?(player, creature)
    end

    test "forced reactions override standing and at-war in both directions" do
      friendly_player =
        player(alliance(), 1, %{29 => %{rank: :hostile, at_war?: true, forced_rank: :friendly}})

      hostile_player =
        player(alliance(), 2, %{29 => %{rank: :honored, at_war?: false, forced_rank: :hostile}})

      creature = mob(wolf(), faction_can_have_reputation?: false)

      assert Hostility.friendly?(friendly_player, creature)
      assert Hostility.friendly?(creature, friendly_player)
      assert Hostility.hostile?(hostile_player, creature)
      assert Hostility.hostile?(creature, hostile_player)
    end

    test "forced reactions override contested guards" do
      player =
        player(alliance(), 1, %{29 => %{rank: :neutral, at_war?: false, forced_rank: :friendly}})
        |> Map.put(:contested_pvp?, true)

      creature = mob(contested_guard(), faction_can_have_reputation?: false)

      assert Hostility.friendly?(player, creature)
      assert Hostility.friendly?(creature, player)
    end

    test "contested guards attack players carrying the contested PvP flag" do
      player =
        player(alliance(), 1, %{29 => %{rank: :honored, at_war?: false}})
        |> Map.put(:contested_pvp?, true)

      creature = mob(contested_guard(), faction_can_have_reputation?: true)

      assert Hostility.hostile?(player, creature)
      assert Hostility.hostile?(creature, player)
    end
  end

  describe "reaction_rank/2" do
    test "preserves exact reputation ranks for creature reactions" do
      player = player(alliance(), 1, %{29 => %{rank: :honored, at_war?: false}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.reaction_rank(creature, player) == :honored
      assert Hostility.reaction_rank(player, creature) == :friendly
    end

    test "caps an at-war creature reaction at neutral" do
      player = player(alliance(), 1, %{29 => %{rank: :exalted, at_war?: true}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.reaction_rank(creature, player) == :neutral
      assert Hostility.reaction_rank(player, creature) == :hostile
    end

    test "returns the exact forced rank in both directions" do
      player = player(alliance(), 1, %{29 => %{rank: :neutral, at_war?: true, forced_rank: :revered}})
      creature = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.reaction_rank(creature, player) == :revered
      assert Hostility.reaction_rank(player, creature) == :revered
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

    test "allows an at-war player to attack a neutral reputation faction" do
      player = player(alliance(), 1, %{29 => %{rank: :neutral, at_war?: true}})
      target = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.valid_attack_target?(player, target)
    end

    test "allows a forced-neutral player to attack a reputation faction" do
      player = player(alliance(), 1, %{29 => %{rank: :friendly, at_war?: false, forced_rank: :neutral}})
      target = mob(wolf(), faction_can_have_reputation?: true)

      assert Hostility.valid_attack_target?(player, target)
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

    test "returns false when VMangos disables proximity aggro" do
      refute Hostility.can_initiate_attack?(%{
               faction_template: defias(),
               unit_flags: 0,
               proximity_aggro?: false
             })
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

  defp contested_guard do
    %{wolf() | flags: 0x1000}
  end

  defp neutral_creature do
    %FactionTemplate{id: 7, faction: 7, flags: 0, faction_group: 0, friend_group: 0, enemy_group: 0}
  end

  defp friendly do
    %FactionTemplate{id: 35, faction: 31, flags: 0, faction_group: 0, friend_group: 1, enemy_group: 0, friends_0: 31}
  end

  defp player(faction_template, low_guid \\ 1, reputation \\ nil) do
    %{
      object: %{guid: Guid.from_low_guid(:player, low_guid)},
      faction_template: faction_template,
      reputation: reputation,
      unit_flags: 0,
      alive?: true
    }
  end

  defp start_duel do
    caster_low = System.unique_integer([:positive])
    target_low = System.unique_integer([:positive])
    caster = player(alliance(), caster_low)
    caster_guid = caster.object.guid
    target_guid = Guid.from_low_guid(:player, target_low)

    :ets.insert(DuelSystem, {caster_guid, %{opponent_guid: target_guid, state: :started}})
    :ets.insert(DuelSystem, {target_guid, %{opponent_guid: caster_guid, state: :started}})

    on_exit(fn ->
      :ets.delete(DuelSystem, caster_guid)
      :ets.delete(DuelSystem, target_guid)
    end)

    target_metadata = %{
      guid: target_guid,
      faction_template: alliance(),
      unit_flags: 0,
      alive?: true
    }

    {caster, target_metadata}
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
