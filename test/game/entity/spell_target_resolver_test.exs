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

  describe "resolve/3" do
    test "returns direct unit targets without world lookup" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 133, effects: []}
      targets = %Targets{unit_guid: 2}

      assert SpellTargetResolver.resolve(caster, spell, targets) == [2]
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
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {x, y, z, 0.0}}
    }
  end

  defp put_spatial_target(table, guid, {x, y, z}) do
    SpatialHash.update(table, guid, 0, x, y, z)
    Metadata.put(guid, %{alive?: true})

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
end
