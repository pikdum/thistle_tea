defmodule ThistleTea.Game.Core.Player.PlayerFlagsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Player.PlayerFlags

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

  describe "contested_pvp?/1" do
    test "reads the contested PvP update-field bit" do
      refute PlayerFlags.contested_pvp?(%Character{player: %Player{flags: 0}})
      assert PlayerFlags.contested_pvp?(%Character{player: %Player{flags: 0x100}})
    end
  end

  describe "toggle_hidden/2" do
    test "flips the helm and cloak bits independently and broadcasts the change" do
      character = %Character{player: %Player{flags: 0x20}, internal: %Internal{}}

      helmless = PlayerFlags.toggle_hidden(character, :helm)
      assert helmless.player.flags == 0x420
      assert helmless.internal.broadcast_update?
      assert PlayerFlags.hidden?(helmless, :helm)
      refute PlayerFlags.hidden?(helmless, :cloak)

      bare = PlayerFlags.toggle_hidden(helmless, :cloak)
      assert bare.player.flags == 0xC20
      assert PlayerFlags.toggle_hidden(bare, :helm).player.flags == 0x820
    end
  end
end
