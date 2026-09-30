defmodule ThistleTea.Game.Inbound.CmsgSetSelectionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Inbound.CmsgSetSelection

  describe "handle/2" do
    test "publishes selection changes while preserving target-bound combo points" do
      character = %Character{
        object: %Object{guid: 5},
        unit: %Unit{target: 77},
        player: %Player{field_combo_target: 77, combo_points: 5},
        internal: %Internal{}
      }

      state = Inbound.handle(%CmsgSetSelection{guid: 0}, %{character: character, target: 77})

      assert state.character.unit.target == 0
      assert state.character.player.field_combo_target == 77
      assert state.character.player.combo_points == 5
      assert state.character.internal.broadcast_update?
    end
  end
end
