defmodule ThistleTea.Game.Entity.Logic.EnchantmentsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Enchantments
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  setup [:character_and_enchant]

  describe "bound?/3" do
    test "temporary binding lasts only as long as its enchant", %{item: item} do
      get = fn
        323 -> %ItemEnchantment{flags: 1}
        41 -> %ItemEnchantment{flags: 0}
        _ -> nil
      end

      poisoned =
        item |> Item.put_permanent_enchantment(41) |> Item.put_temporary_enchantment(323, 1000, 1, 1000, :token)

      assert Enchantments.bound?(poisoned, 999, get)
      refute Enchantments.bound?(poisoned, 1000, get)
      refute Enchantments.bound?(Item.spend_enchantment_charge(poisoned, :token), 999, get)
      assert Enchantments.bound?(Item.put_permanent_enchantment(item, 323), 2000, get)
      assert Enchantments.bound?(%{item | item: %{item.item | flags: 1}}, 2000, get)
    end
  end

  describe "validate/3" do
    test "requires an owned compatible item of sufficient level", %{character: character, item: item, spell: spell} do
      assert :ok = Enchantments.validate(character, spell, item)
      assert {:error, :item_gone} = Enchantments.validate(character, spell, nil)
      assert {:error, :bad_targets} = Enchantments.validate(character, spell, %{item | item: %{item.item | owner: 2}})

      assert {:error, :bad_targets} =
               Enchantments.validate(character, %{spell | equipped_item_inventory_type_mask: 256}, item)

      assert {:error, :lowlevel} = Enchantments.validate(character, %{spell | base_level: 50}, item)

      assert {:error, :caster_dead} =
               Enchantments.validate(%{character | unit: %{character.unit | health: 0}}, spell, item)
    end

    test "validates target equipment rather than the caster weapon and requires a rod", context do
      %{character: character, item: item, spell: spell} = context
      spell = %{spell | tools: [6218]}
      opts = [enchant_item: item, equipped_items: [], count_item: fn 6218 -> 1 end]
      assert :ok = CastValidation.validate(character, spell, Target.item(10), nil, 0, opts)
      opts = Keyword.put(opts, :count_item, fn _ -> 0 end)
      assert {:error, :item_gone} = CastValidation.validate(character, spell, Target.item(10), nil, 0, opts)
    end

    test "temporary coatings validate their target without permanent enchant level restrictions", context do
      %{character: character, item: item, spell: spell} = context
      spell = %{spell | base_level: 60, effects: [%Effect{type: :enchant_item_temporary}]}
      assert :ok = CastValidation.validate(character, spell, Target.item(10), nil, 0, enchant_item: item)
      assert {:error, :item_gone} = Enchantments.validate(character, spell, nil)
      assert {:error, :bad_targets} = Enchantments.validate(character, %{spell | equipped_item_class: 2}, item)
      assert Enchantments.target_guid(%Player{mainhand: 10}, spell, nil) == 10
      assert Enchantments.target_guid(%Player{mainhand: 10}, spell, 20) == 20
    end
  end

  describe "skill_up/3" do
    test "honors recipe thresholds and trained cap", %{character: character} do
      recipe = %{skill_id: 333, yellow: 70, gray: 110}

      for {value, roll, gain} <- [{1, 99, 1}, {70, 74, 1}, {70, 75, 0}, {90, 24, 1}, {90, 25, 0}, {110, 0, 0}] do
        character = %{character | player: %{character.player | skills: %{333 => %{value: value, max: 150}}}}
        assert Enchantments.skill_up(character, recipe, roll).player.skills[333].value == value + gain
      end

      capped = %{character | player: %{character.player | skills: %{333 => %{value: 75, max: 75}}}}
      assert Enchantments.skill_up(capped, recipe, 0) == capped
    end
  end

  defp character_and_enchant(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, level: 10},
      player: %Player{},
      internal: %Internal{}
    }

    item = Item.build(%ItemTemplate{entry: 100, class: 4, subclass: 1, inventory_type: 9, item_level: 10}, 10, owner: 1)

    spell = %Spell{
      id: 7418,
      equipped_item_class: 4,
      equipped_item_inventory_type_mask: Bitwise.bsl(1, 9),
      effects: [%Effect{type: :enchant_item}]
    }

    %{character: character, item: item, spell: spell}
  end
end
