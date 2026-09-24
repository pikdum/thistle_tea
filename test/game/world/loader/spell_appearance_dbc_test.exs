defmodule ThistleTea.Game.World.Loader.SpellAppearanceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.World.Loader.ModelGeometry
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  setup [:model_cache]

  describe "load/1" do
    test "Orb of Deception selects all eight races and both genders" do
      spell = SpellLoader.load(16_739)

      expected = %{
        1 => [10_137, 10_138],
        2 => [10_139, 10_140],
        3 => [10_141, 10_142],
        4 => [10_143, 10_144],
        5 => [10_146, 10_145],
        6 => [10_136, 10_147],
        7 => [10_148, 10_149],
        8 => [10_135, 10_134]
      }

      for {race, displays} <- expected, {display, gender} <- Enum.with_index(displays) do
        entity = entity(race, gender)
        {transformed, _events} = Aura.apply_spell(entity, 1, 60, spell, 1_000)
        assert transformed.unit.display_id == display
        assert {transformed.unit.race, transformed.unit.gender} == {race, gender}
        {restored, _events} = Aura.cancel_spell(transformed, spell.id, 2_000)
        assert restored.unit.display_id == entity.unit.native_display_id
        assert restored.object.scale_x == entity.object.base_scale_x
      end
    end

    test "Orb of Deception scales gnome and tauren disguises using native model scale" do
      spell = SpellLoader.load(16_739)

      for {race, gender, expected} <- [
            {7, 0, 1.35 / 1.15},
            {7, 1, 1.25 / 1.15},
            {6, 0, 1.15 / 1.35},
            {6, 1, 1.15 / 1.25}
          ] do
        {transformed, _events} = Aura.apply_spell(entity(race, gender), 1, 60, spell, 1_000)
        assert_in_delta transformed.object.scale_x, expected, 0.0001
      end
    end

    test "shapeshift models include their geometry and form scale" do
      spell = SpellLoader.load(2645)
      {wolf, _events} = Aura.apply_spell(entity(2, 0), 1, 60, spell, 1_000)
      assert wolf.unit.display_id == 4613
      assert wolf.object.scale_x == 0.8
      model = ModelGeometry.get(4613)
      assert_in_delta wolf.unit.combat_reach, model.combat_reach * 0.8, 0.0001
    end
  end

  defp model_cache(_context) do
    saved = :ets.tab2list(ModelGeometry)
    ModelGeometry.load_all()

    on_exit(fn ->
      :ets.delete_all_objects(ModelGeometry)
      :ets.insert(ModelGeometry, saved)
    end)

    :ok
  end

  defp entity(race, gender) do
    %{
      object: %Object{guid: 1, scale_x: 1.0, base_scale_x: 1.0},
      unit: %Unit{
        race: race,
        gender: gender,
        health: 100,
        max_health: 100,
        level: 60,
        display_id: 49,
        native_display_id: 49,
        auras: [],
        bounding_radius: 0.389,
        combat_reach: 1.5,
        base_bounding_radius: 0.389,
        base_combat_reach: 1.5
      },
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
