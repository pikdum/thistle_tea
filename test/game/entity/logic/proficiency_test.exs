defmodule ThistleTea.Game.Entity.Logic.ProficiencyTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Proficiency
  alias ThistleTea.Game.Spell, as: SpellData
  alias ThistleTea.Game.Spell.Effect

  @staves 1 <<< 10
  @wands 1 <<< 19
  @cloth 1 <<< 1

  defp proficiency_spell(id, item_class, mask) do
    %SpellData{
      id: id,
      equipped_item_class: item_class,
      equipped_item_subclass_mask: mask,
      effects: [%Effect{index: 0, type: :proficiency}]
    }
  end

  defp spellbook(spells), do: Map.new(spells, fn spell -> {spell.id, spell} end)

  describe "from_spellbook/1" do
    test "accumulates weapon and armor masks from proficiency effects" do
      prof =
        spellbook([
          proficiency_spell(227, 2, @staves),
          proficiency_spell(5009, 2, @wands),
          proficiency_spell(9078, 4, @cloth)
        ])
        |> Proficiency.from_spellbook()

      assert prof.weapon_mask == (@staves ||| @wands)
      assert prof.armor_mask == @cloth
      refute prof.dual_wield?
    end

    test "grants dual wield from a dual wield effect" do
      dual_wield = %SpellData{id: 674, effects: [%Effect{index: 0, type: :dual_wield}]}

      assert %Proficiency{dual_wield?: true} = Proficiency.from_spellbook(spellbook([dual_wield]))
    end

    test "ignores non-proficiency effects and handles nil" do
      fireball = %SpellData{id: 133, effects: [%Effect{index: 0, type: :school_damage}]}

      assert Proficiency.from_spellbook(spellbook([fireball])) == %Proficiency{}
      assert Proficiency.from_spellbook(nil) == %Proficiency{}
    end
  end

  describe "can_equip?/2" do
    test "checks weapon subclass bits" do
      prof = %Proficiency{weapon_mask: @staves}

      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 2, subclass: 10}) == :ok
      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 2, subclass: 15}) == {:error, :no_required_proficiency}
    end

    test "checks armor subclass bits" do
      prof = %Proficiency{armor_mask: @cloth}

      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 4, subclass: 1}) == :ok
      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 4, subclass: 2}) == {:error, :no_required_proficiency}
    end

    test "skips subclasses with no proficiency skill" do
      prof = %Proficiency{}

      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 4, subclass: 0}) == :ok
      assert Proficiency.can_equip?(prof, %ItemTemplate{class: 2, subclass: 14}) == :ok
    end

    test "skips non-weapon non-armor items" do
      assert Proficiency.can_equip?(%Proficiency{}, %ItemTemplate{class: 0, subclass: 0}) == :ok
    end
  end
end
