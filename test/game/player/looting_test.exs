defmodule ThistleTea.Game.Player.LootingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Release
  alias ThistleTea.Game.Entity.Logic.Loot.Reservation
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.Looting

  describe "open/3" do
    test "closes pocket viewing before opening a corpse window" do
      parent = self()
      guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))

      spawn_link(fn ->
        Entity.register(guid)
        send(parent, :registered)

        receive do
          {:"$gen_call", from, {:pocket_loot, _actor, :release}} ->
            send(parent, :pockets_released)
            GenServer.reply(from, :ok)
        end

        receive do
          {:"$gen_call", from, {:loot_view, _actor}} ->
            send(parent, :corpse_opened)
            GenServer.reply(from, {:ok, %Loot{gold: 10}})
        end
      end)

      assert_receive :registered

      character = %Character{
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        object: %Object{guid: 42},
        unit: %Unit{health: 100},
        player: %Player{},
        internal: %Internal{}
      }

      state = %State{guid: 42, character: character, loot_guid: guid, loot_type: :pickpocket}
      opened = Looting.open(state, guid)
      assert opened.loot_type == :corpse
      assert opened.loot_guid == guid
      assert_receive :pockets_released
      assert_receive :corpse_opened
    end
  end

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
