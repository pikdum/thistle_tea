defmodule ThistleTea.Game.Spell.CastContextTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.World.Loader.Item

  describe "from_caster/3" do
    test "enchanted weapons retain their normalization and weapon-specific talent bonuses" do
      for {subclass, inventory_type, speed} <- [{7, 13, 2.4}, {15, 13, 1.7}, {8, 17, 3.3}] do
        template = %ItemTemplate{
          entry: 99_887_766 + subclass,
          class: 2,
          subclass: subclass,
          inventory_type: inventory_type
        }

        :ets.insert(Item, {template.entry, template})
        on_exit(fn -> :ets.delete(Item, template.entry) end)

        talent = %Holder{
          spell: %Spell{id: 900_001, equipped_item_class: 2, equipped_item_subclass_mask: Bitwise.bsl(1, subclass)},
          auras: [%Aura{type: :mod_damage_percent_done, amount: 25, misc_value: 1}]
        }

        character = %Character{
          object: %Object{guid: 5},
          unit: %Unit{level: 60, class: 1, auras: [talent]},
          player: %Player{visible_item_16_0: template.entry},
          internal: %Internal{}
        }

        spell = %Spell{id: 900_002, dmg_class: 2, school: :physical}
        plain = character |> Character.sync_equipment_stats() |> CastContext.from_caster(spell, 7)
        assert plain.normalized_speed == speed
        assert plain.damage_done_multiplier == 1.25

        for enchantments <- [Bitwise.bsl(1900, 32), Bitwise.bsl(263, 64), Bitwise.bsl(1900, 32) + Bitwise.bsl(263, 64)] do
          character = %{character | player: %{character.player | visible_item_16_0: template.entry + enchantments}}
          assert character |> Character.sync_equipment_stats() |> CastContext.from_caster(spell, 7) == plain
        end
      end
    end
  end
end
