defmodule ThistleTea.Game.Entity.Logic.Aura.StealthSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura.StealthSync

  describe "sync/1" do
    test "projects untrackable without disturbing other visibility flags" do
      holder = %Holder{auras: [%Aura{type: :untrackable}]}
      character = %Character{unit: %Unit{auras: [holder], vis_flag: 0x01}, player: %Player{}}

      hidden = StealthSync.sync(character)
      restored = StealthSync.sync(%{hidden | unit: %{hidden.unit | auras: []}})

      assert hidden.unit.vis_flag == 0x05
      assert restored.unit.vis_flag == 0x01
    end

    test "projects stalked and empathy into DBC dynamic flags" do
      holder = %Holder{auras: [%Aura{type: :mod_stalked}, %Aura{type: :empathy}]}
      character = %Character{unit: %Unit{auras: [holder], dynamic_flags: 0x20}, player: %Player{}}

      marked = StealthSync.sync(character)
      restored = StealthSync.sync(%{marked | unit: %{marked.unit | auras: []}})

      assert marked.unit.dynamic_flags == 0x32
      assert restored.unit.dynamic_flags == 0x20
    end
  end
end
