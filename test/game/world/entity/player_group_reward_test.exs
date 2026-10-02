defmodule ThistleTea.Game.World.Entity.PlayerGroupRewardTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Combat.DamageOrigin
  alias ThistleTea.Game.Core.Combat.GroupReward.Award
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.Reputation, as: ReputationCore
  alias ThistleTea.Game.Core.Reputation.Catalog
  alias ThistleTea.Game.Core.Reputation.Definition
  alias ThistleTea.Game.Core.Reputation.KillReward
  alias ThistleTea.Game.Core.Reputation.Variant
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.Reputation
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Test.Unique

  setup [:reward_context]

  describe "handle_cast/2" do
    @tag :vmangos_db
    test "NPC pets award reduced XP alongside quest and reputation credit", context do
      victim = %{
        context.victim
        | object: %{context.victim.object | guid: Guid.runtime(:pet, 299)},
          internal: %{
            context.victim.internal
            | pet: %Pet{kind: :creature_pet, owner_guid: Guid.runtime(:mob, 1)},
              damage_origin: %DamageOrigin{player: 100}
          }
      }

      state = %{
        context.state
        | character: %{
            context.state.character
            | internal: %{
                context.state.character.internal
                | rest_bonus: 0.0
              }
          }
      }

      assert {:noreply, updated} = PlayerServer.handle_cast({:reward_kill, victim}, state)
      assert updated.character.player.xp == 81
      assert Reputation.standing(updated.character, 529) == 10
      assert QuestLog.get(updated.character.player.quest_log, context.quest.id).counts == %{0 => 1}

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgLogXpgain{total_exp: 71, experience_without_rested: 71}}}

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgQuestupdateAddKill{count: 1}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetFactionStanding{standings: [{13, 10}]}}}
    end

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
    guid = Unique.integer()
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
        reputation: ReputationCore.initialize(catalog, 1, 1)
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
