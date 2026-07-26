defmodule ThistleTea.Game.Player.SpellsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Network.Message.SmsgSetProficiency
  alias ThistleTea.Game.Player.Spells
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "apply_default_auras/2" do
    test "starts a stanceless warrior in battle stance" do
      battle_stance = stance_spell(2457, 17)

      warrior =
        character(1, %{battle_stance.id => battle_stance})
        |> Spells.apply_default_auras(1_000)

      assert warrior.unit.shapeshift_form == 17
      assert Enum.map(warrior.unit.auras, & &1.spell.id) == [2457]
    end

    test "preserves an existing warrior stance" do
      battle_stance = stance_spell(2457, 17)
      defensive_stance = stance_spell(71, 18)

      warrior =
        character(1, %{battle_stance.id => battle_stance})
        |> Spells.apply_default_auras(1_000)
        |> then(fn warrior ->
          {warrior, _events} =
            Aura.apply_spell(warrior, warrior.object.guid, warrior.unit.level, defensive_stance, 2_000)

          warrior
        end)
        |> Spells.apply_default_auras(3_000)

      assert warrior.unit.shapeshift_form == 18
      assert Enum.map(warrior.unit.auras, & &1.spell.id) == [71]
    end

    test "does not apply battle stance to another class" do
      battle_stance = stance_spell(2457, 17)
      mage = character(8, %{battle_stance.id => battle_stance})

      assert Spells.apply_default_auras(mage, 1_000) == mage
    end
  end

  describe "send_proficiencies/1" do
    test "advertises fishing-pole proficiency when Fishing is known" do
      character = %Character{
        player: %Player{skills: %{356 => %{value: 1, max: 75, range: :tier, always_max?: false}}},
        internal: %Internal{spellbook: %{}}
      }

      assert :ok = Spells.send_proficiencies(character)

      assert_received {:"$gen_cast", {:send_packet, %SmsgSetProficiency{item_class: 2, subclass_mask: mask}}}
      assert (mask &&& 1 <<< 20) != 0
      assert_received {:"$gen_cast", {:send_packet, %SmsgSetProficiency{item_class: 4}}}
    end
  end

  defp character(class, spellbook) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{class: class, level: 1, health: 100, max_health: 100, auras: [], shapeshift_form: 0},
      player: %Player{},
      internal: %Internal{spellbook: spellbook}
    }
  end

  defp stance_spell(id, form) do
    %Spell{
      id: id,
      school: :physical,
      duration_ms: -1,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_shapeshift, base_points: -1, misc_value: form}
      ]
    }
  end
end
