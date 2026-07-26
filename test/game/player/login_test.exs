defmodule ThistleTea.Game.Player.LoginTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Player.Login

  describe "restore_companion/1" do
    test "does not resummon the saved pet while the character is dead" do
      state = %{character: character(health: 0)}

      assert Login.restore_companion(state) == state
    end

    test "does not resummon the saved pet while the character is a ghost" do
      ghost = character(health: 1, player_flags: 0x10)
      refute Death.alive?(ghost)

      state = %{character: ghost}

      assert Login.restore_companion(state) == state
    end
  end

  defp character(opts) do
    %Character{
      object: %Object{guid: 6},
      player: %Player{flags: Keyword.get(opts, :player_flags, 0)},
      unit: %Unit{health: Keyword.fetch!(opts, :health), max_health: 100},
      internal: %Internal{companion: %Companion{kind: :guardian, status: {:suspended, 416, 688}}}
    }
  end
end
