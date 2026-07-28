defmodule ThistleTea.Game.Player.SpellcastingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Player.Spellcasting

  describe "complete/1" do
    test "schedules the repeat loop after Auto Shot activates" do
      character = %Character{
        unit: %Unit{health: 100, max_health: 100},
        internal: %Internal{auto_shot: %{target_guid: 42}}
      }

      state = Spellcasting.complete(%{character: character, player_tick_ref: nil})

      assert is_reference(state.player_tick_ref)
      assert_receive :player_tick
    end
  end
end
