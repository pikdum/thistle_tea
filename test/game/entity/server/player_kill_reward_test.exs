defmodule ThistleTea.Game.Entity.Server.PlayerKillRewardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgLogXpgain
  alias ThistleTea.Game.World.Metadata

  describe "handle_cast/2" do
    test "preserves capped-player rested XP and still forwards the pet's group reward" do
      pet_guid = Guid.from_low_guid(:pet, 1, System.unique_integer([:positive]))
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      Entity.register(pet_guid)
      on_exit(fn -> Metadata.delete(player_guid) end)

      character =
        %Character{
          object: %Object{guid: player_guid},
          unit: %Unit{health: 100, level: 60},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          player: %Player{xp: 0, next_level_xp: 0},
          internal: %Internal{rest_bonus: 1_000.0}
        }
        |> Companion.activate(:hunter_pet, %EntityRef{guid: pet_guid, entry: 1, spell_id: 1515})

      victim = %Mob{
        object: %Object{guid: Guid.from_low_guid(:mob, 1, 1)},
        unit: %Unit{level: 60},
        internal: %Internal{creature: %Creature{experience_multiplier: 1.0}}
      }

      state = %State{guid: player_guid, character: character}
      assert {:noreply, state} = PlayerServer.handle_cast({:reward_kill_share, victim, 100}, state)
      assert state.character.player.xp == 0
      assert state.character.internal.rest_bonus == 1_000.0
      assert_receive {:reward_pet_kill, ^player_guid, 60, {:group, 100}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgLogXpgain{}}}
    end
  end
end
