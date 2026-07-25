defmodule ThistleTea.Game.Player.LootingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Looting

  describe "accept_reservation/3" do
    test "releases the slot when inventory placement fails" do
      parent = self()
      loot_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))

      owner =
        spawn_link(fn ->
          Entity.register(loot_guid)
          send(parent, :registered)

          receive do
            {:"$gen_cast", %Release{} = release} -> send(parent, {:released, release})
          end
        end)

      assert_receive :registered
      token = make_ref()

      reservation = %Reservation{
        token: token,
        slot: 0,
        actor_guid: player_guid,
        item: %Loot.Item{slot: 0, item_id: -1, count: 1},
        release_blocked?: false
      }

      state = %{guid: player_guid}
      assert ^state = Looting.accept_reservation(state, loot_guid, reservation)
      assert_receive {:released, %Release{token: ^token, actor_guid: ^player_guid}}

      Process.unlink(owner)
    end
  end
end
