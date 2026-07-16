defmodule ThistleTea.Game.Entity.Logic.PlayerFlagsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Logic.PlayerFlags

  describe "set_group_leader/2" do
    test "sets the group leader bit without changing other flags" do
      character = %Character{player: %Player{flags: 0x20}}

      character = PlayerFlags.set_group_leader(character, true)

      assert character.player.flags == 0x21
      assert PlayerFlags.group_leader?(character)
    end

    test "clears only the group leader bit" do
      character = %Character{player: %Player{flags: 0x21}}

      character = PlayerFlags.set_group_leader(character, false)

      assert character.player.flags == 0x20
      refute PlayerFlags.group_leader?(character)
    end
  end
end
