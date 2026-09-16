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
    test "combines tracking bits and clears removed resource auras" do
      holder = %Holder{
        auras: [
          %Aura{type: :track_resources, misc_value: 2},
          %Aura{type: :track_resources, misc_value: 7},
          %Aura{type: :track_creatures, misc_value: 1},
          %Aura{type: :track_creatures, misc_value: 7}
        ]
      }

      character = %Character{unit: %Unit{auras: [holder]}, player: %Player{}}
      tracked = PlayerSync.sync(character)
      assert tracked.player.track_resources == 0x42
      assert tracked.player.track_creatures == 0x41
      cleared = PlayerSync.sync(%{tracked | unit: %{tracked.unit | auras: []}})
      assert cleared.player.track_resources == 0
      assert cleared.player.track_creatures == 0
    end

    test "ignores tracking values outside the client field" do
      auras = for value <- [nil, -1, 0, 33, 1.5], do: %Aura{type: :track_resources, misc_value: value}
      character = %Character{unit: %Unit{auras: [%Holder{auras: auras}]}, player: %Player{}}
      assert PlayerSync.sync(character).player.track_resources == 0
    end

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
