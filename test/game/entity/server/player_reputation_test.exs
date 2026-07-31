defmodule ThistleTea.Game.Entity.Server.PlayerReputationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Reputation
  alias ThistleTea.Game.Entity.Data.Reputation.State, as: ReputationState
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata

  describe "threat_ref_gained" do
    test "marks the attacking mob faction temporarily at war" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive, :monotonic]))
      mob_guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))

      Metadata.put(mob_guid, %{
        alive?: true,
        incarnation_id: 7,
        faction_template: %FactionTemplate{faction: 529}
      })

      on_exit(fn -> Metadata.delete(mob_guid) end)

      reputation = %Reputation{
        states: %{529 => %ReputationState{faction_id: 529, index: 13, flags: 0x01}},
        ranks: %{529 => :neutral}
      }

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{},
        player: %Player{reputation: reputation},
        internal: %Internal{}
      }

      state = %State{guid: player_guid, character: character}

      assert {:noreply, %State{character: character} = state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:threat_ref_gained, mob_guid, 7}, state)

      if is_reference(state.player_tick_ref), do: Process.cancel_timer(state.player_tick_ref)

      assert character.player.reputation.temporary_at_war == MapSet.new([529])

      assert Enum.any?(
               character.internal.events,
               &match?(%Effects.FactionAtWarChanged{index: 13, enabled: true}, &1)
             )
    end
  end
end
