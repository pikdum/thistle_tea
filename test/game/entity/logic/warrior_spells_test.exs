defmodule ThistleTea.Game.Entity.Logic.WarriorSpellsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets

  @battle_form 17
  @defensive_form 18

  @battle_stance_mask 0x10000
  @berserker_stance_mask 0x40000

  defp warrior_fixture(opts \\ []) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        level: 10,
        health: 100,
        max_health: 100,
        power_type: 1,
        power2: Keyword.get(opts, :rage, 0),
        max_power2: 1_000,
        shapeshift_form: Keyword.get(opts, :form, 0),
        auras: [],
        flags: 0
      },
      player: %Player{flags: 0},
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp stance_spell(id, form, opts \\ []) do
    %Spell{
      id: id,
      name: Keyword.get(opts, :name, "Stance #{id}"),
      school: :physical,
      duration_ms: -1,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, base_points: -1, misc_value: form},
        %Effect{
          index: 1,
          type: :apply_aura,
          aura: :mod_threat,
          base_points: Keyword.get(opts, :threat, -21),
          misc_value: 127
        }
      ]
    }
  end

  defp apply_stance(entity, spell) do
    {entity, _events} = Aura.apply_spell(entity, entity.object.guid, 10, spell, 1_000)
    entity
  end

  describe "stance application" do
    test "sets the shapeshift form byte" do
      entity = apply_stance(warrior_fixture(), stance_spell(2457, @battle_form))

      assert entity.unit.shapeshift_form == @battle_form
      assert [%Holder{spell: %Spell{id: 2457}}] = entity.unit.auras
    end

    test "zeroes rage on stance change" do
      entity = apply_stance(warrior_fixture(rage: 500), stance_spell(2457, @battle_form))

      assert entity.unit.power2 == 0
    end

    test "switching stances replaces the previous stance holder" do
      entity =
        warrior_fixture()
        |> apply_stance(stance_spell(2457, @battle_form))
        |> apply_stance(stance_spell(71, @defensive_form))

      assert entity.unit.shapeshift_form == @defensive_form
      assert [%Holder{spell: %Spell{id: 71}}] = entity.unit.auras
    end

    test "removing the stance clears the form byte" do
      entity = apply_stance(warrior_fixture(), stance_spell(2457, @battle_form))

      {entity, _events} = Aura.remove_spells(entity, [2457], 2_000)

      assert entity.unit.shapeshift_form == 0
      assert entity.unit.auras == []
    end
  end

  describe "usable_in_stance?/2" do
    test "spells without stance requirements always pass" do
      assert Spell.usable_in_stance?(%Spell{stances: 0}, 0)
      assert Spell.usable_in_stance?(%Spell{stances: 0}, @battle_form)
    end

    test "stance-locked spells require a matching form" do
      spell = %Spell{stances: @battle_stance_mask}

      assert Spell.usable_in_stance?(spell, @battle_form)
      refute Spell.usable_in_stance?(spell, @defensive_form)
      refute Spell.usable_in_stance?(spell, 0)
    end

    test "combined masks accept any listed stance" do
      spell = %Spell{stances: @battle_stance_mask ||| @berserker_stance_mask}

      assert Spell.usable_in_stance?(spell, @battle_form)
      assert Spell.usable_in_stance?(spell, 19)
      refute Spell.usable_in_stance?(spell, @defensive_form)
    end
  end

  describe "stance cast validation" do
    defp overpower_like do
      %Spell{
        id: 7384,
        name: "Overpower",
        school: :physical,
        stances: @battle_stance_mask,
        mana_cost: 0,
        power_type: 1
      }
    end

    test "rejects stance-locked spells outside the stance" do
      caster = warrior_fixture(form: @defensive_form)

      assert {:error, :only_shapeshift} =
               CastValidation.validate(caster, overpower_like(), %Targets{}, nil, 1_000)
    end

    test "accepts stance-locked spells in the required stance" do
      caster = warrior_fixture(form: @battle_form)

      assert :ok = CastValidation.validate(caster, overpower_like(), %Targets{}, nil, 1_000)
    end
  end
end
