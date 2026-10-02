defmodule ThistleTea.Game.Core.Player.PlayedTimeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Player.PlayedTime

  describe "seconds/2" do
    test "counts only time since login and folds idempotently" do
      character = %Character{internal: %Internal{}}
      assert PlayedTime.first_login?(character)

      character = PlayedTime.start(character, 10_000)
      assert PlayedTime.seconds(character, 75_500) == {65, 65}

      character = PlayedTime.fold(character, 40_000)
      character = PlayedTime.fold(character, 40_000)
      assert PlayedTime.seconds(character, 75_500) == {65, 65}
      refute PlayedTime.first_login?(character)

      relogged = PlayedTime.start(character, 1_000_000)
      assert PlayedTime.seconds(relogged, 1_002_000) == {32, 32}
    end
  end

  describe "level_changed/2" do
    test "restarts the level counter and keeps the total" do
      character = %Character{internal: %Internal{}} |> PlayedTime.start(0) |> PlayedTime.level_changed(90_000)
      assert PlayedTime.seconds(character, 120_000) == {120, 30}
    end
  end
end
