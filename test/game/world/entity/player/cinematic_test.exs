defmodule ThistleTea.Game.World.Entity.Player.CinematicTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Player.Cinematic
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.World.Entity.Player.Cinematic, as: PlayerCinematic
  alias ThistleTea.Game.World.Entity.Player.State

  @waypoints [{0, {500.0, 500.0, 0.0}}, {1_000, {600.0, 500.0, 0.0}}]

  describe "update/1" do
    test "drops a camera whose path ran out before the client reported the cinematic over" do
      cinematic = %Cinematic{
        sequence_id: 81,
        started_at: Time.now() - 100_000,
        start: {0.0, 0.0, 0.0},
        waypoints: @waypoints
      }

      assert PlayerCinematic.update(%State{cinematic: cinematic}).cinematic == nil
    end

    test "waits for the player to enter the world before its clock starts" do
      cinematic = Cinematic.prepare(81, @waypoints, {0.0, 0.0, 0.0, 0.0})
      state = %State{cinematic: cinematic}
      assert PlayerCinematic.update(state) == state
      assert is_integer(PlayerCinematic.begin(state).cinematic.started_at)
    end
  end

  describe "CMSG_COMPLETE_CINEMATIC" do
    test "ends the cinematic camera" do
      cinematic = %Cinematic{sequence_id: 81, started_at: Time.now(), start: {0.0, 0.0, 0.0}, waypoints: @waypoints}
      message = Inbound.CmsgCompleteCinematic.from_binary(<<>>)
      assert Inbound.handle(message, %State{cinematic: cinematic}).cinematic == nil
    end
  end
end
