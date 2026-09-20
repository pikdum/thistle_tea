defmodule ThistleTea.Game.Entity.Logic.Honor.ContributionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.Data.Honor.Participant
  alias ThistleTea.Game.Entity.Logic.Honor.Contribution

  describe "record/4" do
    test "accumulates player and nonplayer damage until a minute of inactivity" do
      history =
        %Damage{}
        |> Contribution.record(1, 100, 0)
        |> Contribution.record(nil, 50, 30_000)
        |> Contribution.record(2, 200, 80_000)

      assert history.by_player == %{1 => 100, 0 => 50, 2 => 200}
      assert Contribution.current(history, 140_000) == history
      assert Contribution.current(history, 140_001) == %Damage{}
      assert Contribution.record(history, 1, 100, 140_001).by_player == %{1 => 100}
    end

    test "ignores zero damage and does not rewind the inactivity deadline" do
      history = Contribution.record(%Damage{}, 1, 100, 500)
      assert Contribution.record(history, 2, 0, 60_000) == history
      assert Contribution.record(history, 2, 100, 400).last_damage_at == 500
    end
  end

  describe "shares/4" do
    test "rewards contribution rather than only the killing blow" do
      history = %Damage{by_player: %{1 => 300, 2 => 100, 0 => 100}, last_damage_at: 500}
      shares = Contribution.shares(history, [participant(1), participant(2)], :horde, 500)

      assert_in_delta shares[1], 0.6, 0.0001
      assert_in_delta shares[2], 0.2, 0.0001
    end

    test "does not redistribute absent, dead, distant, or friendly players' damage" do
      participants = [
        participant(1),
        %{participant(2) | alive?: false},
        %{participant(3) | in_range?: false},
        %{participant(4) | team: :horde}
      ]

      history = %Damage{by_player: %{1 => 100, 2 => 100, 3 => 100, 4 => 100, 5 => 100}, last_damage_at: 500}

      assert Contribution.shares(history, participants, :horde, 500) == %{1 => 0.2}
      assert Contribution.shares(history, participants, :horde, 60_501) == %{}
    end

    test "shares group damage with eligible members who did not deal damage" do
      participants = [
        %{participant(1) | group_id: 7},
        %{participant(2) | group_id: 7},
        %{participant(3) | group_id: 7},
        %{participant(4) | group_id: 7, alive?: false},
        participant(5)
      ]

      history = %Damage{by_player: %{1 => 300, 4 => 100, 5 => 100}, last_damage_at: 500}
      shares = Contribution.shares(history, participants, :horde, 500)

      for guid <- [1, 2, 3], do: assert_in_delta(shares[guid], 0.8 * 1.166 / 3, 0.0001)
      refute Map.has_key?(shares, 4)
      assert shares[5] == 0.2
    end

    test "applies the large-group penalty instead of the five-player bonus" do
      participants = for guid <- 1..10, do: %{participant(guid) | group_id: 7}
      history = %Damage{by_player: %{1 => 100}, last_damage_at: 500}

      assert Contribution.shares(history, participants, :horde, 500) == Map.new(1..10, &{&1, 0.05})
    end

    test "returns no rewards when a contributing group has no eligible members" do
      participants = [%{participant(1) | group_id: 7, alive?: false}]
      history = %Damage{by_player: %{1 => 100}, last_damage_at: 500}

      assert Contribution.shares(history, participants, :horde, 500) == %{}
    end
  end

  defp participant(guid), do: %Participant{guid: guid, team: :alliance, alive?: true, in_range?: true}
end
