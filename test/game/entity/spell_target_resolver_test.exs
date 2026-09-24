defmodule ThistleTea.Game.Entity.SpellTargetResolverTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Position
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  describe "resolve/3" do
    test "friendly areas include allies and self but exclude enemies dead actors and other copies" do
      [source, ally, dead, distant, foreign] = for _ <- 1..5, do: mob_guid()
      enemy = player_guid()

      for {guid, position} <- [
            {source, {0.0, 0.0, 0.0}},
            {ally, {3.0, 0.0, 0.0}},
            {dead, {2.0, 0.0, 0.0}},
            {distant, {11.0, 0.0, 0.0}},
            {foreign, {3.0, 0.0, 0.0}}
          ] do
        put_spatial_target(:mobs, guid, position)
      end

      put_spatial_target(:players, enemy, {1.0, 0.0, 0.0})
      Metadata.update(dead, %{alive?: false})
      SpatialHash.update(:mobs, foreign, WorldRef.instance(0, 77), 3.0, 0.0, 0.0)

      spell = %Spell{
        effects: [
          %Effect{
            type: :heal,
            implicit_target_a: :caster_source,
            implicit_target_b: :aoe_ally_at_source,
            radius_yards: 10.0
          }
        ]
      }

      assert Enum.sort(SpellTargetResolver.resolve(caster(source, {0.0, 0.0, 0.0}), spell, Target.unit(enemy))) ==
               Enum.sort([source, ally])
    end

    test "friendly destination areas use the ground center instead of the caster or selected enemy" do
      source = mob_guid()
      friend = mob_guid()
      enemy = player_guid()
      put_spatial_target(:mobs, source, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, friend, {25.0, 0.0, 0.0})
      put_spatial_target(:players, enemy, {25.0, 0.0, 0.0})
      spell = %Spell{effects: [%Effect{type: :heal, implicit_target_a: :aoe_ally_at_dest, radius_yards: 5.0}]}

      assert SpellTargetResolver.resolve(caster(source, {0.0, 0.0, 0.0}), spell, Target.at({25.0, 0.0, 0.0})) == [
               friend
             ]
    end

    test "party buffs follow subgroups while class-wide blessings cross the raid" do
      [leader, moved, other] = guids = for _ <- 1..3, do: player_guid()
      pet = Guid.runtime(:pet, 2960)
      :ok = PartySystem.invite(leader, "Leader", moved)
      {:ok, _} = PartySystem.accept(moved, "Moved")
      :ok = PartySystem.invite(leader, "Leader", other)
      {:ok, _} = PartySystem.accept(other, "Other")
      {:ok, _} = PartySystem.convert_raid(leader)
      {:ok, _} = PartySystem.change_subgroup(leader, moved, 1)
      on_exit(fn -> Enum.each(guids, &PartySystem.leave/1) end)

      for guid <- guids do
        put_spatial_target(:players, guid, {1.0, 0.0, 0.0})
        Metadata.update(guid, %{class: if(guid == other, do: 1, else: 8)})
      end

      put_spatial_target(:mobs, pet, {2.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: moved})
      caster = caster(leader, {1.0, 0.0, 0.0})
      party_buff = aoe_spell(:party_around_caster)
      class_buff = aoe_spell(:raid_and_class)
      assert Enum.sort(SpellTargetResolver.resolve(caster, party_buff, Target.none())) == Enum.sort([leader, other])

      assert Enum.sort(SpellTargetResolver.resolve(caster, class_buff, Target.unit(moved))) ==
               Enum.sort([leader, moved])

      {:ok, _} = PartySystem.change_subgroup(leader, moved, 0)
      assert Enum.sort(SpellTargetResolver.resolve(caster, party_buff, Target.none())) == Enum.sort([pet | guids])
    end

    test "party buffs include the owner's pet and the casting pet" do
      owner = player_guid()
      pet = Guid.runtime(:pet, 2960)
      stranger = player_guid()
      unrelated = Guid.runtime(:pet, 1766)
      put_spatial_target(:players, owner, {0.0, 0.0, 0.0})
      put_spatial_target(:players, stranger, {1.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {2.0, 0.0, 0.0})
      put_spatial_target(:mobs, unrelated, {3.0, 0.0, 0.0})
      Metadata.put(pet, %{alive?: true, owner_guid: owner})
      Metadata.put(unrelated, %{alive?: true, owner_guid: stranger})
      spell = aoe_spell(:party_around_caster)
      pet_caster = Map.put(caster(pet, {2.0, 0.0, 0.0}), :unit, %Unit{created_by: owner})

      assert Enum.sort(SpellTargetResolver.resolve(pet_caster, spell, Target.none())) == Enum.sort([owner, pet])

      assert Enum.sort(SpellTargetResolver.resolve(caster(owner, {0.0, 0.0, 0.0}), spell, Target.none())) ==
               Enum.sort([owner, pet])

      Metadata.put(pet, %{alive?: false, owner_guid: owner})
      assert SpellTargetResolver.resolve(caster(owner, {0.0, 0.0, 0.0}), spell, Target.none()) == [owner]
    end

    test "targeted party buffs follow the selected member's subgroup and position" do
      [caster_guid, selected, nearby, other_subgroup] = guids = for _ <- 1..4, do: player_guid()
      pet = Guid.runtime(:pet, 2960)
      low_level_pet = Guid.runtime(:pet, 2960)
      :ok = PartySystem.invite(caster_guid, "Caster", selected)
      {:ok, _} = PartySystem.accept(selected, "Selected")
      :ok = PartySystem.invite(caster_guid, "Caster", nearby)
      {:ok, _} = PartySystem.accept(nearby, "Nearby")
      :ok = PartySystem.invite(caster_guid, "Caster", other_subgroup)
      {:ok, _} = PartySystem.accept(other_subgroup, "Other")
      {:ok, _} = PartySystem.convert_raid(caster_guid)
      {:ok, _} = PartySystem.change_subgroup(caster_guid, selected, 1)
      {:ok, _} = PartySystem.change_subgroup(caster_guid, nearby, 1)
      on_exit(fn -> Enum.each(guids, &PartySystem.leave/1) end)

      put_spatial_target(:players, caster_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:players, selected, {30.0, 0.0, 0.0})
      put_spatial_target(:players, nearby, {35.0, 0.0, 0.0})
      put_spatial_target(:players, other_subgroup, {32.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {34.0, 0.0, 0.0})
      put_spatial_target(:mobs, low_level_pet, {36.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: selected})
      Metadata.update(low_level_pet, %{owner_guid: nearby})

      spell = aoe_spell(:party_around_target)
      casting_player = caster(caster_guid, {0.0, 0.0, 0.0})

      assert Enum.sort(SpellTargetResolver.resolve(casting_player, spell, Target.unit(selected))) ==
               Enum.sort([selected, nearby, pet, low_level_pet])

      assert Enum.sort(SpellTargetResolver.resolve(casting_player, spell, Target.unit(pet))) ==
               Enum.sort([selected, nearby, pet, low_level_pet])

      assert SpellTargetResolver.resolve(casting_player, spell, Target.unit(other_subgroup)) ==
               [other_subgroup]

      Metadata.update(selected, %{level: 50})
      Metadata.update(nearby, %{level: 37})
      Metadata.update(other_subgroup, %{level: 50})
      high_rank = %{spell | spell_level: 48}

      assert Enum.sort(SpellTargetResolver.resolve(casting_player, high_rank, Target.unit(selected))) ==
               Enum.sort([selected, pet])
    end

    test "targeted party buffs include an ungrouped friend and its nearby pet" do
      caster_guid = player_guid()
      friend = player_guid()
      pet = Guid.runtime(:pet, 2960)
      put_spatial_target(:players, caster_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:players, friend, {5.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {7.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: friend})

      spell = aoe_spell(:party_around_target)
      casting_player = caster(caster_guid, {0.0, 0.0, 0.0})

      assert Enum.sort(SpellTargetResolver.resolve(casting_player, spell, Target.unit(friend))) ==
               Enum.sort([friend, pet])

      assert Enum.sort(SpellTargetResolver.resolve(casting_player, %{spell | spell_level: 48}, Target.unit(friend))) ==
               Enum.sort([friend, pet])

      assert SpellTargetResolver.resolve(casting_player, spell, Target.unit(mob_guid())) == []
    end

    test "party-only spells permit the owner's group and pets but reject self and strangers" do
      [owner, member, stranger] = guids = for _ <- 1..3, do: player_guid()
      pet = Guid.runtime(:pet, 2960)
      member_pet = Guid.runtime(:pet, 2960)
      :ok = PartySystem.invite(owner, "Owner", member)
      {:ok, _} = PartySystem.accept(member, "Member")
      on_exit(fn -> Enum.each(guids, &PartySystem.leave/1) end)

      for guid <- guids, do: put_spatial_target(:players, guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, member_pet, {0.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: owner})
      Metadata.update(member_pet, %{owner_guid: member})

      spell = aoe_spell(:party_member)
      player_caster = caster(owner, {0.0, 0.0, 0.0})
      pet_caster = Map.put(caster(pet, {0.0, 0.0, 0.0}), :unit, %Unit{created_by: owner})

      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(pet)) == [pet]
      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(member)) == [member]
      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(member_pet)) == [member_pet]
      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(owner)) == []
      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(stranger)) == []
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(owner)) == [owner]
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(pet)) == []

      Metadata.update(member, %{alive?: false})
      assert SpellTargetResolver.resolve(player_caster, spell, Target.unit(member)) == []
    end

    test "an ungrouped pet can target its owner but not another player" do
      owner = player_guid()
      stranger = player_guid()
      pet = Guid.runtime(:pet, 2960)
      put_spatial_target(:players, owner, {0.0, 0.0, 0.0})
      put_spatial_target(:players, stranger, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {0.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: owner})

      spell = aoe_spell(:party_member)
      pet_caster = Map.put(caster(pet, {0.0, 0.0, 0.0}), :unit, %Unit{created_by: owner})

      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(owner)) == [owner]
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(stranger)) == []
    end

    test "pet spells reach their master and preserve a separate caster effect" do
      owner = player_guid()
      stranger = player_guid()
      pet = Guid.runtime(:pet, 2960)
      put_spatial_target(:players, owner, {0.0, 0.0, 0.0})
      put_spatial_target(:players, stranger, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {0.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: owner})

      spell = %Spell{
        id: 7812,
        custom_flags: 4,
        effects: [
          %Effect{type: :apply_aura, implicit_target_a: :caster_master},
          %Effect{type: :instakill, implicit_target_a: :caster}
        ]
      }

      pet_caster = Map.put(caster(pet, {0.0, 0.0, 0.0}), :unit, %Unit{created_by: owner})
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.none()) == [owner, pet]
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(stranger)) == [owner, pet]
      assert SpellTargetResolver.resolve(caster(owner, {0.0, 0.0, 0.0}), spell, Target.none()) == [owner]
    end

    test "mixed enemy and master effects reach both recipients" do
      owner = player_guid()
      enemy = player_guid()
      pet = Guid.runtime(:pet, 2961)
      put_spatial_target(:players, owner, {0.0, 0.0, 0.0})
      put_spatial_target(:players, enemy, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, pet, {0.0, 0.0, 0.0})
      Metadata.update(pet, %{owner_guid: owner})

      spell = %Spell{
        id: 24_826,
        effects: [
          %Effect{type: :school_damage, implicit_target_a: :target_enemy},
          %Effect{type: :apply_aura, implicit_target_a: :target_enemy, implicit_target_b: :caster_master}
        ]
      }

      pet_caster = Map.put(caster(pet, {0.0, 0.0, 0.0}), :unit, %Unit{created_by: owner})
      assert SpellTargetResolver.resolve(pet_caster, spell, Target.unit(enemy)) == [owner, enemy]
    end

    test "returns direct unit targets without world lookup" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 133, effects: []}
      targets = Target.unit(2)

      assert SpellTargetResolver.resolve(caster, spell, targets) == [2]
    end

    test "executes untargeted summon effects on the caster" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 1122, effects: [%Effect{type: :summon_demon}]}

      assert SpellTargetResolver.resolve(caster, spell, Target.at({1.0, 2.0, 3.0})) == [1]
    end

    test "resolves mixed enemy and caster effects to both owners" do
      caster = %{object: %{guid: 1}}

      spell = %Spell{
        effects: [
          %Effect{type: :modify_threat, implicit_target_a: :target_enemy},
          %Effect{type: :apply_aura, implicit_target_a: :caster}
        ]
      }

      assert SpellTargetResolver.resolve(caster, spell, Target.unit(2)) == [2, 1]
    end

    test "chains through nearest valid targets using DBC chain count" do
      player_guid = player_guid()
      first = mob_guid()
      second = mob_guid()
      third = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, first, {5.0, 0.0, 0.0})
      put_spatial_target(:mobs, second, {14.0, 0.0, 0.0})
      put_spatial_target(:mobs, third, {23.0, 0.0, 0.0})

      caster = caster(player_guid, {0.0, 0.0, 0.0})

      spell = %Spell{
        attributes: MapSet.new([:ignore_line_of_sight]),
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy, chain_targets: 3}]
      }

      assert SpellTargetResolver.resolve(caster, spell, Target.unit(first)) == [first, second, third]
    end

    test "returns nearby mobs for player-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [mob_guid]
    end

    test "centers caster aoe on projected client motion" do
      player_guid = player_guid()
      mob_guid = mob_guid()
      now = System.monotonic_time(:millisecond)

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {7.0, 0.0, 0.0})

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      projection = Position.client_motion(caster, {70.0, 0.0, 0.0}, now - 100, 750)
      Position.put(caster, :players, projection)

      spell = %Spell{
        effects: [%Effect{type: :school_damage, implicit_target_a: :aoe_enemy_at_caster, radius_yards: 3.0}]
      }

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [mob_guid]
    end

    test "DBC creature mask filters caster AoE targets" do
      player_guid = player_guid()
      undead_guid = mob_guid()
      humanoid_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, undead_guid, {3.0, 0.0, 0.0})
      put_spatial_target(:mobs, humanoid_guid, {4.0, 0.0, 0.0})
      Metadata.update(undead_guid, %{creature_type: 6})
      Metadata.update(humanoid_guid, %{creature_type: 7})

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = %{aoe_spell(:aoe_enemy_at_caster) | target_creature_type_mask: 36}

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [undead_guid]
    end

    test "dismiss pet bypasses the creature mask without metadata" do
      caster =
        %Character{object: %{guid: 1}, unit: %Unit{}, internal: %Internal{}}
        |> Companion.activate(:hunter_pet, %EntityRef{guid: 7, entry: 2960, spell_id: 1515})

      spell = %Spell{
        id: 2641,
        target_creature_type_mask: 1,
        effects: [%Effect{type: :dismiss_pet, implicit_target_a: :pet}]
      }

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [7, 1]
    end

    test "returns nearby attackable neutral mobs for player-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0}, neutral_creature())

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [mob_guid]
    end

    test "returns nearby players for mob-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(mob_guid, {3.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, Target.none()) == [player_guid]
    end

    test "returns nearby mobs for player-cast targeted aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {40.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(player_guid, {40.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_dest)
      targets = Target.at({0.0, 0.0, 0.0})

      assert SpellTargetResolver.resolve(caster, spell, targets) == [mob_guid]
    end

    test "returns nearby players for mob-cast targeted aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {3.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {40.0, 0.0, 0.0})

      caster = caster(mob_guid, {40.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_channel)
      targets = Target.at({0.0, 0.0, 0.0})

      assert SpellTargetResolver.resolve(caster, spell, targets) == [player_guid]
    end

    test "caster cone hits enemies in front and excludes the caster and targets behind" do
      player_guid = player_guid()
      front_mob_guid = mob_guid()
      behind_mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, front_mob_guid, {3.0, 0.0, 0.0})
      put_spatial_target(:mobs, behind_mob_guid, {-3.0, 0.0, 0.0})

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_in_cone)

      assert SpellTargetResolver.resolve(caster, spell, Target.unit(front_mob_guid)) == [front_mob_guid]
    end
  end

  describe "resolve_query/2" do
    test "returns direct unit query targets" do
      caster = %{object: %{guid: 1}}

      assert SpellTargetResolver.resolve_query(caster, {:unit, 2}) == [2]
    end

    test "resolves targeted aoe queries against world state" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {40.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(player_guid, {40.0, 0.0, 0.0})

      assert SpellTargetResolver.resolve_query(caster, {:targeted_aoe, {0.0, 0.0, 0.0}, 10.0}) == [mob_guid]
    end
  end

  defp player_guid do
    Guid.from_low_guid(:player, bounded_unique(0xFFFFFFFF))
  end

  defp mob_guid do
    Guid.from_low_guid(:mob, 1, bounded_unique(0x00FFFFFF))
  end

  defp bounded_unique(max) do
    rem(System.unique_integer([:positive]), max) + 1
  end

  defp caster(guid, {x, y, z}) do
    %{
      object: %{guid: guid},
      internal: %Internal{world: %WorldRef{map_id: 0}},
      movement_block: %MovementBlock{position: {x, y, z, 0.0}}
    }
  end

  defp put_spatial_target(table, guid, {x, y, z}) do
    put_spatial_target(table, guid, {x, y, z}, faction_template(table))
  end

  defp put_spatial_target(table, guid, {x, y, z}, faction_template) do
    SpatialHash.update(table, guid, 0, x, y, z)

    Metadata.put(guid, %{
      alive?: true,
      faction_template: faction_template,
      faction_can_have_reputation?: false,
      unit_flags: 0
    })

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)
  end

  defp aoe_spell(target) do
    %Spell{
      id: 122,
      effects: [
        %Effect{
          implicit_target_a: target,
          radius_yards: 10.0
        }
      ]
    }
  end

  defp faction_template(:players) do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp faction_template(:mobs) do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end

  defp neutral_creature do
    %FactionTemplate{id: 7, faction: 7, flags: 0, faction_group: 0, friend_group: 0, enemy_group: 0}
  end
end
