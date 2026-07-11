defmodule ThistleTea.Game.Network.Message.CmsgSetSelectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgSetSelection

  describe "handle/2" do
    test "keeps target-bound combo points when temporarily deselecting" do
      character = %Character{
        object: %Object{guid: 5},
        unit: %Unit{target: 77},
        player: %Player{field_combo_target: 77, combo_points: 5},
        internal: %Internal{}
      }

      state = CmsgSetSelection.handle(%CmsgSetSelection{guid: 0}, %{character: character, target: 77})

      assert state.character.unit.target == 0
      assert state.character.player.field_combo_target == 77
      assert state.character.player.combo_points == 5
      refute state.character.internal.broadcast_update?
    end
  end
end
