defmodule ThistleTea.CharacterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Character
  alias ThistleTea.Game.Network.Message.CmsgCharCreate

  describe "build/2" do
    test "uses Mangos race/class level stats for new characters" do
      character = Character.build(char_create(), 1)

      assert character.unit.level == 1
      assert character.unit.health == 60
      assert character.unit.max_health == 60
      assert character.unit.power1 == 0
      assert character.unit.max_power1 == 0
      assert character.unit.max_power2 == 1000
      assert character.unit.strength == 23
      assert character.unit.agility == 20
      assert character.unit.stamina == 22
      assert character.unit.intellect == 20
      assert character.unit.spirit == 21
      assert character.unit.base_health == 20
      assert character.unit.base_mana == 0
      assert character.player.xp == 0
      assert character.player.next_level_xp == 400
    end
  end

  describe "gain_xp/2" do
    test "levels up and carries remaining XP" do
      character = Character.build(char_create(), 1)

      {character, [level_up]} = Character.gain_xp(character, 450)

      assert character.unit.level == 2
      assert character.unit.health == 79
      assert character.unit.max_health == 79
      assert character.unit.strength == 24
      assert character.unit.agility == 21
      assert character.unit.stamina == 23
      assert character.player.xp == 50
      assert character.player.next_level_xp == 900

      assert level_up == %{
               new_level: 2,
               health: 19,
               mana: 0,
               rage: 0,
               focus: 0,
               energy: 0,
               happiness: 0,
               strength: 1,
               agility: 1,
               stamina: 1,
               intellect: 0,
               spirit: 0
             }
    end
  end

  defp char_create do
    %CmsgCharCreate{
      name: "Test",
      race: 1,
      class: 1,
      gender: 0,
      skin_color: 1,
      face: 1,
      hair_style: 1,
      hair_color: 1,
      facial_hair: 1,
      outfit_id: 1
    }
  end
end
