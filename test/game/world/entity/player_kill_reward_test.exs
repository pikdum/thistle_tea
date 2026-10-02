defmodule ThistleTea.Game.World.Entity.PlayerKillRewardTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Combat.GroupReward.Award
  alias ThistleTea.Game.Core.Combat.KillFeedback
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Network.Message.SmsgLogXpgain
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "handle_cast/2" do
    test "fatal blows notify the active pet even when the victim is gray" do
      pet_guid = Guid.runtime(:pet, 1)
      player_guid = Unique.integer()
      {:ok, _} = Entity.register(pet_guid)

      character =
        %Character{object: %Object{guid: player_guid}, unit: %Unit{health: 100, level: 60}, internal: %Internal{}}
        |> Companion.activate(:hunter_pet, %EntityRef{guid: pet_guid, entry: 1, spell_id: 1515})

      victim = %KillFeedback.Victim{guid: Guid.runtime(:mob, 38), level: 4, reward_target?: true}
      state = %State{guid: player_guid, character: character}

      assert {:noreply, ^state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:kill_outcome, victim}, state)

      assert_receive {:owner_killed, ^player_guid, guid}
      assert guid == victim.guid
    end

    test "preserves capped-player rested XP and still forwards the pet's group reward" do
      pet_guid = Guid.from_low_guid(:pet, 1, Unique.integer())
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      {:ok, _} = Entity.register(pet_guid)
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

      assert {:noreply, state} =
               PlayerServer.handle_cast(
                 {:reward_kill_share, victim, %Award{xp: 100, pet_xp: 100, pet_max_level: 60, quest?: true}},
                 state
               )

      assert state.character.player.xp == 0
      assert state.character.internal.rest_bonus == 1_000.0
      assert_receive {:reward_pet_kill, ^player_guid, 60, {:group, 100, 60}}
      refute_received {:"$gen_cast", {:send_packet, %SmsgLogXpgain{}}}
    end
  end
end
