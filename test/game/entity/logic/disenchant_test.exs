defmodule ThistleTea.Game.Entity.Logic.DisenchantTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Disenchant
  alias ThistleTea.Game.Entity.Logic.ItemLoot
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:enchanter]

  describe "validate_item/2" do
    test "allows level-one enchanting to disenchant high-level equipment", %{character: character, item: item} do
      assert :ok = Disenchant.validate_item(character, item)
    end

    test "rejects missing, foreign, non-disenchantable, and flagged items", %{character: character, item: item} do
      for invalid <- [
            nil,
            %{item | item: %{item.item | owner: 2}},
            %{item | item: %{item.item | stack_count: 2}},
            Item.build(%ItemTemplate{entry: 1}, 10, owner: 1),
            Item.build(%ItemTemplate{entry: 1, disenchant_id: 1, flags: 0x8000}, 10, owner: 1)
          ] do
        assert {:error, :cant_be_disenchanted} = Disenchant.validate_item(character, invalid)
      end
    end

    test "requires a living enchanter without unclaimed materials", %{character: character, item: item} do
      assert {:error, :low_castlevel} = Disenchant.validate_item(%{character | player: %Player{skills: %{}}}, item)
      assert {:error, :caster_dead} = Disenchant.validate_item(%{character | unit: %{character.unit | health: 0}}, item)
      pending = ItemLoot.new(item, %Loot{})
      character = %{character | internal: %{character.internal | item_loot: pending}}
      assert {:error, :already_open} = Disenchant.validate_item(character, item)
    end
  end

  describe "validate/6" do
    test "validates item-targeted disenchant through shared cast admission", %{character: character, item: item} do
      spell = %Spell{id: 13_262, effects: [%Effect{type: :disenchant}]}
      assert :ok = CastValidation.validate(character, spell, Target.item(10), nil, 0, disenchant_item: item)
      assert {:error, :cant_be_disenchanted} = CastValidation.validate(character, spell, Target.item(10), nil, 0)
      assert :ok = Disenchant.validate(character, %Spell{}, nil)
    end
  end

  describe "skill_up/2" do
    test "uses vanilla orange, yellow, green, and gray thresholds", %{character: character} do
      for {value, chance} <- [{1, 100}, {19, 100}, {20, 75}, {39, 75}, {40, 25}, {59, 25}, {60, 0}] do
        character = put_in(character.player.skills[333].value, value)
        assert Disenchant.gain_chance(value) == chance
        assert Disenchant.skill_up(character, chance).player.skills[333].value == value

        if chance > 0 do
          assert Disenchant.skill_up(character, chance - 1).player.skills[333].value == value + 1
        end
      end
    end

    test "never exceeds the trained cap", %{character: character} do
      character = put_in(character.player.skills[333].max, 1)
      assert Disenchant.skill_up(character, 0) == character
    end
  end

  defp enchanter(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, level: 1},
      player: %Player{skills: %{333 => %{value: 1, max: 75, range: :tier}}},
      internal: %Internal{}
    }

    item = Item.build(%ItemTemplate{entry: 1, disenchant_id: 1, item_level: 60}, 10, owner: 1)
    %{character: character, item: item}
  end
end
