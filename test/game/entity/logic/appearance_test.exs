defmodule ThistleTea.Game.Entity.Logic.AppearanceTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Logic.Appearance
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Aura.ObjectSync
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.ScriptEquipment
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "polymorphed?/1" do
    test "regeneration follows the selected transformation through replacement and expiry", %{character: character} do
      character = %{character | unit: %{character.unit | health: 50}, internal: %{character.internal | in_combat: true}}

      polymorph = %{
        disguise(118, 856)
        | spell_family: 3,
          prevention_type: 1,
          attributes: MapSet.new([:negative]),
          effects: [
            %Effect{index: 0, type: :apply_aura, aura: :mod_confuse},
            %Effect{index: 1, type: :apply_aura, aura: :transform, appearance: %Model{display_id: 856}}
          ]
      }

      {sheep, _events} = Aura.apply_spell(character, 2, 60, polymorph, 1_000)
      {disguised, _events} = Aura.apply_spell(sheep, 1, 60, disguise(900_001, 100), 2_000)
      assert Appearance.polymorphed?(disguised.unit)
      assert Regen.tick(disguised, 2_000).unit.health == 60

      overriding = %{disguise(900_002, 200) | attributes: MapSet.new([:negative]), duration_ms: 1_000}
      {overridden, _events} = Aura.apply_spell(disguised, 3, 60, overriding, 3_000)
      refute Appearance.polymorphed?(overridden.unit)
      assert Regen.tick(overridden, 3_000).unit.health == 50

      {revealed, _events} = Aura.expire_due(overridden, 4_000)
      assert Appearance.polymorphed?(revealed.unit)
      assert Regen.tick(revealed, 4_000).unit.health == 60

      {expired, _events} = Aura.expire_due(revealed, 11_000)
      refute Appearance.polymorphed?(expired.unit)
      assert Regen.tick(expired, 11_000).unit.health == 50

      {removed, _events} = Aura.remove_spells(sheep, [118], 2_000)
      refute Appearance.polymorphed?(removed.unit)
      assert Regen.tick(removed, 2_000).unit.health == 50
    end
  end

  describe "apply_spell/5" do
    test "newer disguises replace the display and reveal the older one on removal", %{character: character} do
      {first, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, 100), 1_000)
      {second, _events} = Aura.apply_spell(first, 1, 60, disguise(900_002, 200), 2_000)
      assert second.unit.display_id == 200
      {removed, _events} = Aura.remove_spells(second, [900_002], 3_000)
      assert removed.unit.display_id == 100
      {removed, _events} = Aura.remove_spells(removed, [900_001], 4_000)
      assert removed.unit.display_id == 49
    end

    test "harmful transforms override both earlier and later disguises", %{character: character} do
      {first, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, 100), 1_000)
      harmful = %{disguise(900_002, 200) | attributes: MapSet.new([:negative])}
      {second, _events} = Aura.apply_spell(first, 2, 60, harmful, 2_000)
      {third, _events} = Aura.apply_spell(second, 1, 60, disguise(900_003, 300), 3_000)
      assert second.unit.display_id == 200
      assert third.unit.display_id == 200
      {removed, _events} = Aura.remove_spells(third, [900_002], 4_000)
      assert removed.unit.display_id == 300
    end

    test "newest harmful transform wins and expiry restores its predecessor", %{character: character} do
      first = %{disguise(900_001, 100) | attributes: MapSet.new([:negative])}
      second = %{disguise(900_002, 200) | attributes: MapSet.new([:negative]), duration_ms: 2_000}
      {entity, _events} = Aura.apply_spell(character, 2, 60, first, 1_000)
      {entity, _events} = Aura.apply_spell(entity, 3, 60, second, 2_000)
      assert entity.unit.display_id == 200
      {expired, _events} = Aura.expire_due(entity, 4_000)
      assert expired.unit.display_id == 100
    end

    test "refreshing changes priority without relying on holder position", %{character: character} do
      {entity, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, 100), 1_000)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, disguise(900_002, 200), 2_000)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, disguise(900_001, 100), 3_000)
      assert entity.unit.display_id == 100
      assert length(entity.unit.auras) == 2
    end

    test "applications at the same timestamp retain application order", %{character: character} do
      {entity, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, 100), 1_000)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, disguise(900_002, 200), 1_000)
      assert entity.unit.display_id == 200
    end

    test "race and gender select a compiled model without changing identity", %{character: character} do
      spell = disguise(900_001, %{{1, 0} => %Model{display_id: 100}, {1, 1} => %Model{display_id: 200}})
      {entity, _events} = Aura.apply_spell(character, 1, 60, spell, 1_000)
      assert {entity.unit.display_id, entity.unit.race, entity.unit.gender} == {100, 1, 0}
      female = %{character | unit: %{character.unit | gender: 1}}
      {entity, _events} = Aura.apply_spell(female, 1, 60, spell, 1_000)
      assert {entity.unit.display_id, entity.unit.race, entity.unit.gender} == {200, 1, 1}
    end
  end

  describe "transition/2" do
    test "scale and geometry are derived without compounding and restore on removal", %{character: character} do
      model = %Model{display_id: 100, scale: 0.8, bounding_radius: 0.5, combat_reach: 2.0}
      {entity, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, model), 1_000)
      assert_in_delta entity.object.scale_x, 0.8, 0.0001
      assert_in_delta entity.unit.bounding_radius, 0.4, 0.0001
      assert_in_delta entity.unit.combat_reach, 1.6, 0.0001
      {scaled, _events} = Aura.apply_spell(entity, 1, 60, growth(), 2_000)
      assert_in_delta scaled.object.scale_x, 1.2, 0.0001
      assert_in_delta scaled.unit.bounding_radius, 0.6, 0.0001
      assert_in_delta scaled.unit.combat_reach, 2.4, 0.0001
      assert ObjectSync.sync(scaled) == scaled

      for cause <- [:cancelled, :removed, :dispelled, :death] do
        {restored, _events} = Aura.transition(scaled, %Change{holders: [], cause: cause, now: 3_000})
        assert restored.object.scale_x == character.object.base_scale_x
        assert restored.unit.bounding_radius == character.unit.base_bounding_radius
        assert restored.unit.combat_reach == character.unit.base_combat_reach
        assert restored.unit.display_id == character.unit.native_display_id
      end
    end

    test "removing only the transform preserves active growth", %{character: character} do
      model = %Model{display_id: 100, scale: 0.8}
      {entity, _events} = Aura.apply_spell(character, 1, 60, disguise(900_001, model), 1_000)
      {entity, _events} = Aura.apply_spell(entity, 1, 60, growth(), 2_000)
      {restored, _events} = Aura.remove_spells(entity, [900_001], 3_000)
      assert_in_delta restored.object.scale_x, 1.5, 0.0001
      assert_in_delta restored.unit.combat_reach, 2.25, 0.0001
      assert restored.unit.display_id == 49
    end

    test "removing a transform restores the shapeshift model and scale", %{character: character} do
      wolf = %Spell{
        id: 2645,
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, misc_value: 16}]
      }

      {entity, _events} = Aura.apply_spell(character, 1, 60, wolf, 1_000)
      assert entity.unit.display_id == 4613
      assert entity.object.scale_x == 0.8
      {entity, _events} = Aura.apply_spell(entity, 1, 60, disguise(900_001, 100), 2_000)
      assert entity.unit.display_id == 100
      assert entity.object.scale_x == 1.0
      {entity, _events} = Aura.remove_spells(entity, [900_001], 3_000)
      assert entity.unit.display_id == 4613
      assert entity.object.scale_x == 0.8
      {entity, _events} = Aura.remove_spells(entity, [2645], 4_000)
      assert entity.unit.display_id == 49
      assert entity.object.scale_x == 1.0
    end

    test "creature equipment follows the selected transform and restores its template", %{character: character} do
      original = ScriptEquipment.apply(character.unit, [item(500), nil, nil])

      mob = %Mob{
        object: character.object,
        unit: original,
        movement_block: character.movement_block,
        internal: %Internal{
          creature: %Creature{
            default_equipment: %{
              virtual_item_slot_display: original.virtual_item_slot_display,
              virtual_item_info: original.virtual_item_info
            }
          }
        }
      }

      first = %Model{display_id: 100, equipment: [item(600), nil, nil]}
      second = %Model{display_id: 200, equipment: [nil, nil, nil]}
      {entity, _events} = Aura.apply_spell(mob, 1, 60, disguise(900_001, first), 1_000)
      assert entity.unit.virtual_item_slot_display == 600
      {entity, _events} = Aura.apply_spell(entity, 1, 60, disguise(900_002, second), 2_000)
      assert entity.unit.virtual_item_slot_display == 0
      {entity, _events} = Aura.remove_spells(entity, [900_002], 3_000)
      assert entity.unit.virtual_item_slot_display == 600
      {entity, _events} = Aura.remove_spells(entity, [900_001], 4_000)
      assert entity.unit.virtual_item_slot_display == 500
      assert entity.unit.virtual_item_info == original.virtual_item_info
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1, scale_x: 1.0, base_scale_x: 1.0},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 60,
          race: 1,
          gender: 0,
          display_id: 49,
          native_display_id: 49,
          bounding_radius: 0.389,
          combat_reach: 1.5,
          base_bounding_radius: 0.389,
          base_combat_reach: 1.5,
          auras: []
        },
        player: %Player{},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp disguise(id, display) when is_integer(display), do: disguise(id, %Model{display_id: display})

  defp disguise(id, appearance) do
    %Spell{
      id: id,
      duration_ms: 10_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :transform, appearance: appearance}]
    }
  end

  defp growth do
    %Spell{
      id: 900_010,
      duration_ms: 10_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_scale, base_points: 50}]
    }
  end

  defp item(display) do
    %ItemTemplate{display_id: display, class: 2, subclass: 7, material: 1, inventory_type: 13, sheath: 1}
  end
end
