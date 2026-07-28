defmodule ThistleTea.Game.Player.ProjectileTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Player.Projectile
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader

  describe "fields/2" do
    test "includes the selected ammo display for ranged spells and repeat effects" do
      ammo_id = System.unique_integer([:positive])
      weapon_id = System.unique_integer([:positive])
      ammo = %ItemTemplate{entry: ammo_id, display_id: 5996, inventory_type: 24}
      weapon = %ItemTemplate{entry: weapon_id, display_id: 123, inventory_type: 15}
      :ets.insert(ItemLoader, {ammo_id, ammo})
      :ets.insert(ItemLoader, {weapon_id, weapon})

      on_exit(fn ->
        :ets.delete(ItemLoader, ammo_id)
        :ets.delete(ItemLoader, weapon_id)
      end)

      auto_shot = %Spell{id: 75, dmg_class: 3}

      character = %Character{
        player: %Player{ammo_id: ammo_id, visible_item_18_0: weapon_id},
        internal: %Internal{spellbook: %{75 => auto_shot}}
      }

      expected = %{flags: 0x20, display_id: 5996, inventory_type: 24}

      assert Projectile.fields(character, auto_shot) == expected
      assert Projectile.fields(character, 75) == expected
    end

    test "uses the ranged weapon itself for thrown attacks" do
      weapon_id = System.unique_integer([:positive])
      weapon = %ItemTemplate{entry: weapon_id, display_id: 256, inventory_type: 25}
      :ets.insert(ItemLoader, {weapon_id, weapon})
      on_exit(fn -> :ets.delete(ItemLoader, weapon_id) end)

      character = %Character{
        player: %Player{ammo_id: 0, visible_item_18_0: weapon_id},
        internal: %Internal{}
      }

      assert Projectile.fields(character, %Spell{id: 2764, dmg_class: 3}) ==
               %{flags: 0x20, display_id: 256, inventory_type: 25}
    end

    test "omits projectile fields from non-ranged spells" do
      character = %Character{player: %Player{ammo_id: 1}, internal: %Internal{}}

      assert Projectile.fields(character, %Spell{id: 133, dmg_class: 1}) ==
               %{flags: 0, display_id: nil, inventory_type: nil}
    end
  end
end
