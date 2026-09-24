defmodule ThistleTea.Game.World.SpellAreasTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Condition.Subject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.World.Loader.Exploration
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpellAreas
  alias ThistleTea.Game.WorldRef

  describe "context/2" do
    setup [:controlled_caster]

    test "uses the caster location and controlling player facts", %{caster: caster, player: player} do
      context = SpellAreas.context(caster)
      assert context.zone_id == 900_100
      assert context.area_id == 900_101
      assert context.player == player
      assert Area.validate(%Spell{area_rules: [%Area{area_id: 900_100, race_mask: 1, gender: 1}]}, context) == :ok
    end

    test "rejects cached areas from a different map", %{caster: caster} do
      caster = %{caster | internal: %{caster.internal | world: %WorldRef{map_id: 900_102}}}
      context = SpellAreas.context(caster)
      assert context.zone_id == nil
      assert context.area_id == nil
    end

    test "does not resolve a location for unrestricted spells", %{caster: caster} do
      assert SpellAreas.context(caster, %Spell{}) == nil
    end
  end

  defp controlled_caster(_context) do
    guid = System.unique_integer([:positive])
    owner = System.unique_integer([:positive])
    player = %Subject{kind: :player, race: 1, gender: 1, zone_id: 1519}
    Metadata.put(guid, %{owner_guid: owner})
    Metadata.put(owner, %{condition_subject: player})
    :ets.insert(Exploration, {{:area, 900_101}, %AreaTable{id: 900_101, map: 900_100, parent_area_table: 900_100}})

    on_exit(fn ->
      Metadata.delete(guid)
      Metadata.delete(owner)
      :ets.delete(Exploration, {:area, 900_101})
    end)

    caster = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{},
      internal: %Internal{area: 900_101, world: %WorldRef{map_id: 900_100}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{caster: caster, player: player}
  end
end
