defmodule ThistleTea.Game.Player.ReputationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Quest
  alias ThistleTea.Game.Entity.Data.Reputation.Catalog
  alias ThistleTea.Game.Entity.Data.Reputation.Definition
  alias ThistleTea.Game.Entity.Data.Reputation.KillReward
  alias ThistleTea.Game.Entity.Data.Reputation.Variant
  alias ThistleTea.Game.Entity.Logic.Reputation, as: ReputationLogic
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Reputation
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Reputation, as: ReputationLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup do
    previous_catalog = ReputationLoader.catalog()
    id = System.unique_integer([:positive, :monotonic])

    on_exit(fn ->
      ReputationLoader.put_catalog(previous_catalog)
      :ets.delete(CharacterStore, id)
      Metadata.delete(Guid.from_low_guid(:player, id))
    end)

    %{id: id}
  end

  describe "modify/4" do
    test "persists, projects, and sends visibility plus standing changes", %{id: id} do
      catalog = catalog([definition(529, 13)])
      state = state(id, catalog)
      ReputationLoader.put_catalog(catalog)

      state = Reputation.modify(state, 529, 250)

      assert Reputation.standing(state.character, 529) == 250
      assert CharacterStore.get(id).player.reputation == state.character.player.reputation
      assert Metadata.get(state.guid).reputation[529] == %{rank: :neutral, at_war?: false}

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetFactionVisible{index: 13}}}

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetFactionStanding{standings: [{13, 250}]}}}
    end
  end

  describe "reward_quest/2" do
    test "applies every translated quest reward", %{id: id} do
      catalog = catalog([definition(529, 13), definition(87, 0)])
      state = state(id, catalog)
      ReputationLoader.put_catalog(catalog)

      quest = %Quest{
        level: 10,
        reward_reputation: [
          %{faction_id: 529, value: 250, no_spillover?: false},
          %{faction_id: 87, value: -25, no_spillover?: true}
        ]
      }

      state = Reputation.reward_quest(state, quest)

      assert Reputation.standing(state.character, 529) == 250
      assert Reputation.standing(state.character, 87) == -25
    end
  end

  describe "reward_kill/3" do
    test "selects the player's team reward and applies the parent team award", %{id: id} do
      catalog =
        catalog(
          [definition(72, 19, 469), definition(469, 11)],
          %{
            123 => [
              %KillReward{
                faction_id: 72,
                value: 10,
                max_rank: 7,
                team: :alliance,
                team_award?: true
              },
              %KillReward{faction_id: 76, value: 10, max_rank: 7, team: :horde}
            ]
          }
        )

      state = state(id, catalog)
      ReputationLoader.put_catalog(catalog)

      state = Reputation.reward_kill(state, 123, 10)

      assert Reputation.standing(state.character, 72) == 10
      assert Reputation.standing(state.character, 469) == 5
      assert Reputation.standing(state.character, 76) == 0
    end
  end

  describe "send_initial/1" do
    test "sends all 64 client slots using standing offsets", %{id: id} do
      catalog = catalog([definition(529, 13)])
      character = state(id, catalog).character
      ReputationLoader.put_catalog(catalog)
      {reputation, _changes} = ReputationLogic.modify(character.player.reputation, catalog, 529, 250, context())
      character = %{character | player: %{character.player | reputation: reputation}}

      Reputation.send_initial(character)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgInitializeFactions{factions: factions}}}

      assert length(factions) == 64
      assert Enum.at(factions, 13) == {0x01, 250}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetForcedReactions{reactions: []}}}
    end

    test "sends and projects active aura-forced reactions", %{id: id} do
      catalog = catalog([definition(575, 20)])
      character = state(id, catalog).character
      ReputationLoader.put_catalog(catalog)

      holder = %Holder{
        spell: %Spell{id: 6405},
        auras: [%AuraData{type: :force_reaction, misc_value: 575, amount: 3}]
      }

      character = %{character | unit: %{character.unit | auras: [holder]}}

      assert Reputation.projection(character)[575] == %{
               rank: :neutral,
               at_war?: false,
               forced_rank: :neutral
             }

      Reputation.send_initial(character)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgSetForcedReactions{reactions: [{575, 3}]}}}
    end
  end

  defp state(id, catalog) do
    guid = Guid.from_low_guid(:player, id)

    character = %Character{
      id: id,
      object: %Object{guid: guid},
      unit: %Unit{race: 1, class: 1, level: 10, auras: []},
      player: %Player{reputation: ReputationLogic.initialize(catalog, 1, 1)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }

    %{guid: guid, character: character}
  end

  defp catalog(definitions, kill_rewards \\ %{}) do
    %Catalog{factions: Map.new(definitions, &{&1.id, &1}), kill_rewards: kill_rewards}
  end

  defp definition(id, index, parent_faction_id \\ 0) do
    %Definition{
      id: id,
      index: index,
      name: "Faction #{id}",
      parent_faction_id: parent_faction_id,
      variants: [%Variant{}]
    }
  end

  defp context, do: %{race: 1, class: 1}
end
