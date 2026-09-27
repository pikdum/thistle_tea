defmodule ThistleTea.Game.MeetingStoneTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.MeetingStone
  alias ThistleTea.Game.MeetingStone.Applicant
  alias ThistleTea.Game.MeetingStone.Roles
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Party.Member

  setup [:players]

  describe "join/5 and leave/3" do
    test "rejects nonleaders, raids, full groups, and offline requests", %{players: players} do
      party = group(players, [1, 2])
      assert {:error, :not_leader} = MeetingStone.join(%MeetingStone{}, party, players[2], 1581, 0)
      {:ok, _group, raid} = Party.convert_raid(party, 1)
      assert {:error, :raid_group} = MeetingStone.join(%MeetingStone{}, raid, players[1], 1581, 0)
      full = group(players, 1..5)
      assert {:error, :full_group} = MeetingStone.join(%MeetingStone{}, full, players[1], 1581, 0)

      assert {:error, :unavailable} =
               MeetingStone.join(%MeetingStone{}, %Party{}, %{players[1] | online?: false}, 1581, 0)

      assert {:error, :unavailable} = MeetingStone.join(%MeetingStone{}, %Party{}, players[1], 0, 0)
    end

    test "queues the party once and only its current leader can withdraw it", %{players: players} do
      party = group(players, [1, 2])
      {:ok, queue, [{:status, [1, 2], 1581, 1}]} = MeetingStone.join(%MeetingStone{}, party, players[1], 1581, 0)
      assert {^queue, [{:status, [2], 0, 5}]} = MeetingStone.leave(queue, party, 2)
      {:ok, _, party} = Party.set_leader(party, 1, 2)
      assert {queue, [{:status, [1, 2], 0, 0}]} = MeetingStone.leave(queue, party, 2)
      assert queue.groups == %{}
    end

    test "replacing a solo destination cannot duplicate its membership", %{players: players} do
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, %Party{}, players[1], 1581, 0)
      {:ok, queue, _} = MeetingStone.join(queue, %Party{}, players[1], 718, 1)
      assert map_size(queue.solos) == 1
      assert MeetingStone.status(queue, %Party{}, 1) == {:status, [1], 718, 1}
      {queue, _} = MeetingStone.leave(queue, %Party{}, 1)
      assert MeetingStone.status(queue, %Party{}, 1) == {:status, [1], 0, 5}
    end
  end

  describe "refresh/4" do
    test "forms a complete balanced party from five compatible solos", %{players: players} do
      queue = enqueue(%MeetingStone{}, %Party{}, players, 1..5)
      {queue, party, events} = MeetingStone.refresh(queue, %Party{}, players, 10)
      group = Party.group_of(party, 1)
      assert Enum.map(group.members, & &1.guid) == [1, 2, 3, 4, 5]
      assert queue == %MeetingStone{}
      assert {:complete, [1, 2, 3, 4, 5]} in events
      assert List.last(events) == {:status, [1, 2, 3, 4, 5], 0, 5}
      assert {^queue, ^party, []} = MeetingStone.refresh(queue, party, players, 11)
    end

    test "fills an existing party by missing roles and preserves group identity", %{players: players} do
      party = group(players, [3, 4])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[3], 1581, 0)
      queue = enqueue(queue, party, players, [1, 2, 5])
      original = Party.group_of(party, 3)
      {queue, party, events} = MeetingStone.refresh(queue, party, players, 20)
      group = Party.group_of(party, 3)
      assert group.id == original.id
      assert group.leader == 3
      assert Enum.map(group.members, & &1.guid) == [3, 4, 1, 2, 5]
      assert queue.groups == %{}
      assert {:complete, [3, 4, 1, 2, 5]} in events
    end

    test "partitions factions and dungeons without starving another cohort", %{players: players} do
      players = players |> Map.put(6, actor(6, 1, :horde)) |> Map.put(7, actor(7, 5))
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, %Party{}, players[6], 1581, -10)
      {:ok, queue, _} = MeetingStone.join(queue, %Party{}, players[7], 718, -10)
      queue = enqueue(queue, %Party{}, players, 1..5)
      {queue, party, _} = MeetingStone.refresh(queue, %Party{}, players, 20)
      assert map_size(party.groups) == 1
      assert Map.keys(queue.solos) |> Enum.sort() == [6, 7]
      assert Party.group_of(party, 6) == nil
      assert Party.group_of(party, 7) == nil
    end

    test "retains offline tickets and respects pending invitations", %{players: players} do
      queue = enqueue(%MeetingStone{}, %Party{}, players, 1..5)
      offline = put_in(players[5].online?, false)
      assert {^queue, %Party{groups: groups}, []} = MeetingStone.refresh(queue, %Party{}, offline, 10)
      assert groups == %{}
      assert MeetingStone.status(queue, %Party{}, 5) == {:status, [5], 1581, 1}
      {:ok, party} = Party.invite(%Party{}, 99, "Other", 5)
      assert {^queue, ^party, []} = MeetingStone.refresh(queue, party, players, 11)
      {:ok, 99, party} = Party.decline(party, 5)
      {queue, party, _} = MeetingStone.refresh(queue, party, players, 12)
      assert queue == %MeetingStone{}
      assert length(Party.group_of(party, 5).members) == 5
    end

    test "does not assign a fourth damage slot or fill an offline leader's party", %{players: players} do
      players = Map.new(1..5, &{&1, %{players[&1] | class: 8}})
      queue = enqueue(%MeetingStone{}, %Party{}, players, 1..5)
      {queue, party, _} = MeetingStone.refresh(queue, %Party{}, players, 10)
      assert length(Party.group_of(party, 1).members) == 3
      assert map_size(queue.solos) == 2
      offline = put_in(players[1].online?, false)
      offline = put_in(offline[4].class, 1)
      assert {^queue, ^party, []} = MeetingStone.refresh(queue, party, offline, 11)
    end

    test "prefers class specialists until a player earns long-wait priority", %{players: players} do
      players = players |> Map.put(6, actor(6, 11)) |> Map.put(7, actor(7, 1))
      party = group(players, [2, 3, 4, 5])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[2], 1581, 0)
      queue = enqueue(queue, party, players, [6, 7])
      {_, specialized, _} = MeetingStone.refresh(queue, party, players, 10)
      assert Party.group_of(specialized, 7)
      assert Party.group_of(specialized, 6) == nil
      queue = put_in(queue.solos[6].queued_at, -1_800_000)
      {_, waiting, _} = MeetingStone.refresh(queue, party, players, 10)
      assert Party.group_of(waiting, 6)
      assert Party.group_of(waiting, 7) == nil
    end
  end

  describe "synchronize/3" do
    test "cancels a departed leader's queue but preserves an explicit leadership transfer", %{players: players} do
      party = group(players, [1, 2, 3])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[1], 1581, 0)
      {:ok, _, departed} = Party.leave(party, 1)
      {cancelled, events} = MeetingStone.synchronize(queue, departed, 1)
      assert cancelled.groups == %{}
      assert {:status, [1, 2, 3], 0, 0} in events
      {:ok, _, transferred} = Party.set_leader(party, 1, 2)
      {retained, []} = MeetingStone.synchronize(queue, transferred, 1)
      assert hd(Map.values(retained.groups)).leader == 2
      assert MeetingStone.status(retained, transferred, 3) == {:status, [3], 1581, 1}
    end

    test "kicking a member withdraws the party and restores the removed player's solo queue", %{players: players} do
      party = group(players, [1, 2, 3])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[1], 1581, 0)
      {:ok, _, remaining} = Party.uninvite(party, 1, 3)
      {queue, events} = MeetingStone.party_changed(queue, party, remaining, {:uninvite, 1, 3}, 10)
      assert queue.groups == %{}
      assert Map.keys(queue.solos) == [3]
      assert events == [{:status, [1, 2], 0, 3}, {:status, [3], 1581, 4}]
      assert MeetingStone.status(queue, remaining, 3) == {:status, [3], 1581, 1}
    end

    test "tracks removals, manual completion, and raid conversion", %{players: players} do
      party = group(players, [1, 2, 3])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[1], 1581, 0)
      {:ok, _, reduced} = Party.leave(party, 3)
      {reduced_queue, events} = MeetingStone.synchronize(queue, reduced, 10)
      assert {:status, [3], 0, 5} in events
      assert {:status, [1, 2], 1581, 2} in events
      assert hd(Map.values(reduced_queue.groups)).members == [1, 2]
      full = Enum.reduce([4, 5], party, fn guid, party -> add(party, players[guid], 1) end)
      {completed, events} = MeetingStone.synchronize(queue, full, 11)
      assert completed.groups == %{}
      assert {:complete, [1, 2, 3, 4, 5]} in events
      {:ok, _, raid} = Party.convert_raid(party, 1)
      assert {%MeetingStone{groups: groups}, [{:status, [1, 2, 3], 0, 0}]} = MeetingStone.synchronize(queue, raid, 12)
      assert groups == %{}
    end

    test "clears disbanded groups and reports progress every five minutes", %{players: players} do
      party = group(players, [1, 2])
      {:ok, queue, _} = MeetingStone.join(%MeetingStone{}, party, players[1], 1581, 0)
      assert {queue, [{:progress, [1, 2]}]} = MeetingStone.synchronize(queue, party, 300_000)
      assert {^queue, []} = MeetingStone.synchronize(queue, party, 300_001)
      {:ok, _, party} = Party.leave(party, 1)
      {queue, events} = MeetingStone.synchronize(queue, party, 300_002)
      assert queue.groups == %{}
      assert {:status, [1, 2], 0, 0} in events
    end
  end

  describe "available/1 and matchmake/4" do
    test "assigns hybrids once and protects ordinary party mutations" do
      assert Roles.available([actor(1, 11), actor(2, 1), actor(3, 5)]) == [:damage, :damage]
      players = Map.new(1..6, &{&1, actor(&1, 8)})
      party = group(players, 1..5)
      group = Party.group_of(party, 1)
      assert {:error, :group_full} = Party.matchmake(party, 1, %Member{guid: 6, name: "Six"}, group.id)
      assert {:error, :unavailable} = Party.matchmake(party, 2, %Member{guid: 6, name: "Six"}, group.id)
      assert {:error, :unavailable} = Party.matchmake(party, 1, %Member{guid: 6, name: "Six"}, group.id + 1)
    end
  end

  defp players(_context),
    do: %{players: Map.new(Enum.zip(1..5, [1, 5, 8, 4, 3]), fn {id, class} -> {id, actor(id, class)} end)}

  defp actor(guid, class, team \\ :alliance),
    do: %Applicant{guid: guid, name: "Player#{guid}", class: class, team: team, online?: true}

  defp enqueue(queue, party, players, ids) do
    Enum.reduce(ids, queue, fn guid, queue ->
      {:ok, queue, _} = MeetingStone.join(queue, party, players[guid], 1581, guid)
      queue
    end)
  end

  defp group(players, ids) do
    [leader | rest] = Enum.to_list(ids)
    Enum.reduce(rest, %Party{}, &add(&2, players[&1], leader))
  end

  defp add(party, actor, leader) do
    {:ok, party} = Party.invite(party, leader, "Player#{leader}", actor.guid)
    {:ok, _, party} = Party.accept(party, actor.guid, actor.name)
    party
  end
end
