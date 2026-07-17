defmodule ThistleTea.Game.Entity.Logic.Aura.PlayerSyncTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [<<<: 2]

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.PlayerSync

  describe "sync/1" do
    test "projects the active creature tracking aura into the player field" do
      holder = %Holder{auras: [%Aura{type: :track_creatures, misc_value: 7}]}
      character = %Character{unit: %Unit{auras: [holder]}, player: %Player{track_creatures: 0}}

      character = PlayerSync.sync(character)

      assert character.player.track_creatures == 1 <<< 6
      assert PlayerSync.sync(%{character | unit: %{character.unit | auras: []}}).player.track_creatures == 0
    end

    test "projects Track Hidden into the DBC player flag" do
      holder = %Holder{auras: [%Aura{type: :track_stealthed}]}
      character = %Character{unit: %Unit{auras: [holder]}, player: %Player{field_bytes_flags: 0x08}}

      tracked = PlayerSync.sync(character)
      restored = PlayerSync.sync(%{tracked | unit: %{tracked.unit | auras: []}})

      assert tracked.player.field_bytes_flags == 0x0A
      assert restored.player.field_bytes_flags == 0x08
    end
  end
end
