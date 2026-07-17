defmodule ThistleTea.Game.Entity.SpellTargetResolverTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "resolve/3" do
    test "returns direct unit targets without world lookup" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 133, effects: []}
      targets = %Targets{unit_guid: 2}

      assert SpellTargetResolver.resolve(caster, spell, targets) == [2]
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
        effects: [%Effect{type: :school_damage, implicit_target_a: :target_enemy, chain_targets: 3}]
      }

      assert SpellTargetResolver.resolve(caster, spell, %Targets{unit_guid: first}) == [first, second, third]
    end

    test "returns nearby mobs for player-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, %Targets{}) == [mob_guid]
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

      assert SpellTargetResolver.resolve(caster, spell, %Targets{}) == [undead_guid]
    end

    test "returns nearby attackable neutral mobs for player-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0}, neutral_creature())

      caster = caster(player_guid, {0.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, %Targets{}) == [mob_guid]
    end

    test "returns nearby players for mob-cast caster aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {0.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(mob_guid, {3.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTargetResolver.resolve(caster, spell, %Targets{}) == [player_guid]
    end

    test "returns nearby mobs for player-cast targeted aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {40.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {3.0, 0.0, 0.0})

      caster = caster(player_guid, {40.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_dest)
      targets = %Targets{destination_location: {0.0, 0.0, 0.0}}

      assert SpellTargetResolver.resolve(caster, spell, targets) == [mob_guid]
    end

    test "returns nearby players for mob-cast targeted aoe" do
      player_guid = player_guid()
      mob_guid = mob_guid()

      put_spatial_target(:players, player_guid, {3.0, 0.0, 0.0})
      put_spatial_target(:mobs, mob_guid, {40.0, 0.0, 0.0})

      caster = caster(mob_guid, {40.0, 0.0, 0.0})
      spell = aoe_spell(:aoe_enemy_at_channel)
      targets = %Targets{destination_location: {0.0, 0.0, 0.0}}

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

      assert SpellTargetResolver.resolve(caster, spell, %Targets{unit_guid: front_mob_guid}) == [front_mob_guid]
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
