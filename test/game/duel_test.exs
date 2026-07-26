defmodule ThistleTea.Game.DuelTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Duel
  alias ThistleTea.Game.Duel.Admission

  describe "lifecycle" do
    test "admits one challenge per player and starts after acceptance" do
      attrs = %{arbiter_guid: 30, world: :world, flag_position: {1.0, 2.0, 3.0}}
      admission = admission(10, 20)

      assert {:ok, requested, duels} = Duel.challenge(%Duel{}, admission, attrs)
      assert requested.state == :requested
      assert Duel.match_for(duels, 10) == requested
      assert Duel.match_for(duels, 20) == requested
      assert {:error, :initiator_busy} = Duel.challenge(duels, admission(10, 40), attrs)
      assert {:error, :opponent_busy} = Duel.challenge(duels, admission(40, 20), attrs)

      assert {:error, :not_opponent} = Duel.accept(duels, 10, 1_000)
      assert {:ok, countdown, duels} = Duel.accept(duels, 20, 1_000)
      assert countdown.state == :countdown
      assert countdown.countdown_started_at == 1_000

      assert {:ok, started, duels} = Duel.start(duels, countdown.id, 4_000)
      assert started.state == :started
      assert started.started_at == 4_000

      assert {:ok, ^started, duels} = Duel.complete(duels, 10)
      assert Duel.match_for(duels, 10) == nil
      assert Duel.match_for(duels, 20) == nil
    end
  end

  describe "check_bounds/4" do
    setup do
      {:ok, _match, duels} =
        Duel.challenge(%Duel{}, admission(10, 20), %{arbiter_guid: 30, flag_position: {0.0, 0.0, 0.0}})

      {:ok, match, duels} = Duel.accept(duels, 20, 0)
      {:ok, match, duels} = Duel.start(duels, match.id, 3_000)
      %{match: match, duels: duels}
    end

    test "uses separate outbound and inbound radii", %{match: match, duels: duels} do
      assert {[{:out_of_bounds, 10}], duels} =
               Duel.check_bounds(duels, match.id, %{10 => 76.0, 20 => 1.0}, 4_000)

      assert {[], duels} = Duel.check_bounds(duels, match.id, %{10 => 72.0, 20 => 1.0}, 5_000)

      assert {[{:in_bounds, 10}], _duels} =
               Duel.check_bounds(duels, match.id, %{10 => 69.0, 20 => 1.0}, 6_000)
    end

    test "forfeits after ten seconds outside", %{match: match, duels: duels} do
      assert {[{:out_of_bounds, 20}], duels} =
               Duel.check_bounds(duels, match.id, %{10 => 1.0, 20 => 80.0}, 4_000)

      assert {[], duels} = Duel.check_bounds(duels, match.id, %{10 => 1.0, 20 => 80.0}, 13_999)

      assert {[{:fled, 20, 10}], ^duels} =
               Duel.check_bounds(duels, match.id, %{10 => 1.0, 20 => 80.0}, 14_000)
    end

    test "forfeits a player whose position disappears", %{match: match, duels: duels} do
      assert {[{:fled, 10, 20}], ^duels} =
               Duel.check_bounds(duels, match.id, %{10 => nil, 20 => 1.0}, 4_000)
    end
  end

  defp admission(initiator_guid, opponent_guid) do
    %Admission{
      initiator_guid: initiator_guid,
      opponent_guid: opponent_guid,
      initiator_player?: true,
      opponent_player?: true,
      initiator_online?: true,
      opponent_online?: true,
      initiator_allowed?: true,
      opponent_allowed?: true,
      same_world?: true,
      initiator_busy?: false,
      opponent_busy?: false
    }
  end
end
