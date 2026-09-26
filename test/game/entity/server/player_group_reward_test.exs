defmodule ThistleTea.Game.Entity.Server.PlayerGroupRewardTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.KillReward
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.GroupReward.Award
  alias ThistleTea.Game.Entity.Logic.QuestLog
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.WorldRef

  setup [:reward_context]

  describe "handle_cast/2" do
    test "awards an unreleased corpse quest credit and full reputation without XP", context do
      state = put_life(context.state, 0, 0)
      assert {:noreply, updated} = PlayerServer.handle_cast({:reward_kill_share, context.victim, context.award}, state)
      assert updated.character.player.xp == 10
      assert updated.character.internal.rest_bonus == 1_000.0
      assert Reputation.standing(updated.character, 529) == 10
      assert QuestLog.get(updated.character.player.quest_log, context.quest.id).counts == %{0 => 1}
      assert CharacterStore.get(state.guid).player.quest_log == updated.character.player.quest_log
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddKill{count: 1}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetFactionStanding{standings: [{13, 10}]}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgLogXpgain{}}}
    end

    test "rechecks release at delivery and retains only reputation", context do
      state = put_life(context.state, 1, 0x10)
      assert {:noreply, updated} = PlayerServer.handle_cast({:reward_kill_share, context.victim, context.award}, state)
      assert updated.character.player.xp == 10
      assert updated.character.internal.rest_bonus == 1_000.0
      assert Reputation.standing(updated.character, 529) == 10
      assert QuestLog.get(updated.character.player.quest_log, context.quest.id).counts == %{}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddKill{}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgLogXpgain{}}}
    end

    test "does not grant solo XP to a ghost with positive health", context do
      state = put_life(context.state, 1, 0x10)
      assert {:noreply, updated} = PlayerServer.handle_cast({:reward_kill, context.victim}, state)
      assert updated.character.player.xp == 10
      assert updated.character.internal.rest_bonus == 1_000.0
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgLogXpgain{}}}
    end
  end

  defp put_life(%State{character: character} = state, health, flags) do
    %{
      state
      | character: %{character | unit: %{character.unit | health: health}, player: %{character.player | flags: flags}}
    }
  end

  defp reward_context(_context) do
    previous = ReputationLoader.catalog()
    guid = System.unique_integer([:positive, :monotonic])
    faction = %Definition{id: 529, index: 13, variants: [%Variant{}]}

    catalog = %Catalog{
      factions: %{529 => faction},
      kill_rewards: %{299 => [%KillReward{faction_id: 529, value: 10, max_rank: 7, team: :both}]}
    }

    ReputationLoader.put_catalog(catalog)
    quest = %Quest{id: 900_000 + guid, required_kills: [{0, 299, 2}]}
    :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
    {:ok, log} = QuestLog.add(%{}, quest.id)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 10, race: 1, class: 1},
      player: %Player{
        quest_log: log,
        xp: 10,
        next_level_xp: 10_000,
        reputation: ReputationLogic.initialize(catalog, 1, 1)
      },
      internal: %Internal{world: WorldRef.open(0), rest_bonus: 1_000.0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    victim = %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 299, 1), entry: 299},
      unit: %Unit{level: 10},
      internal: %Internal{creature: %Creature{experience_multiplier: 1.0}}
    }

    on_exit(fn ->
      ReputationLoader.put_catalog(previous)
      :ets.delete(QuestLoader, {:quest, quest.id})
      :ets.delete(CharacterStore, guid)
      Presence.leave(character)
    end)

    %{
      state: %State{guid: guid, character: character},
      victim: victim,
      quest: quest,
      award: %Award{guid: guid, xp: 47, pet_xp: 47, pet_max_level: 10, quest?: true}
    }
  end
end
