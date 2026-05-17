defmodule ThistleTea.CharacterTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Network.Message.CmsgCharCreate

  @unit_flag_player_controlled 0x00000008
  @unit_flag_use_swim_animation 0x00008000

  describe "build/2" do
    test "sets client-visible player unit flags" do
      character =
        ThistleTea.Character.build(
          %CmsgCharCreate{
            name: "Flagtest",
            race: 1,
            class: 8,
            gender: 0,
            skin_color: 0,
            face: 0,
            hair_style: 0,
            hair_color: 0,
            facial_hair: 0,
            outfit_id: 0
          },
          1
        )

      assert (character.unit.flags &&& @unit_flag_player_controlled) == @unit_flag_player_controlled
      assert (character.unit.flags &&& @unit_flag_use_swim_animation) == @unit_flag_use_swim_animation
    end
  end
end
