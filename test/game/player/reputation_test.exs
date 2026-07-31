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
  alias ThistleTea.Game.Entity.Data.ItemTemplate
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

    test "awards the parent faction after the primary faction rank cap", %{id: id} do
      catalog =
        catalog(
          [definition(72, 19, 469), definition(469, 11)],
          %{
            123 => [
              %KillReward{
                faction_id: 72,
                value: 10,
                max_rank: 4,
                team: :alliance,
                team_award?: true
              }
            ]
          }
        )

      state = state(id, catalog)
      ReputationLoader.put_catalog(catalog)
      character = put_standing(state.character, catalog, 72, 9_000)

      state = Reputation.reward_kill(%{state | character: character}, 123, 10)

      assert Reputation.standing(state.character, 72) == 9_000
      assert Reputation.standing(state.character, 469) == 5
    end

    test "applies general and kill-only faction aura bonuses", %{id: id} do
      catalog =
        catalog(
          [definition(529, 13)],
          %{
            123 => [
              %KillReward{
                faction_id: 529,
                value: 100,
                max_rank: 7,
                team: :alliance
              }
            ]
          }
        )

      state = state(id, catalog)
      ReputationLoader.put_catalog(catalog)

      holder = %Holder{
        spell: %Spell{id: 1},
        auras: [
          %AuraData{type: :mod_reputation_gain, amount: 10},
          %AuraData{type: :mod_faction_reputation_gain, misc_value: 529, amount: 20}
        ]
      }

      character = %{state.character | unit: %{state.character.unit | auras: [holder]}}
      state = Reputation.reward_kill(%{state | character: character}, 123, 10)

      assert Reputation.standing(state.character, 529) == 130

      state = Reputation.reward_spell(state, 529, 100)

      assert Reputation.standing(state.character, 529) == 240
    end
  end

  describe "price/3" do
    test "rounds the honored NPC discount to the nearest copper", %{id: id} do
      catalog = catalog([definition(72, 19)])
      character = state(id, catalog).character
      vendor_guid = vendor_guid(72)
      ReputationLoader.put_catalog(catalog)

      assert Reputation.price(character, vendor_guid, 25) == 25

      character = put_standing(character, catalog, 72, 9_000)

      assert Reputation.price(character, vendor_guid, 25) == 23
    end
  end

  describe "creature access" do
    test "blocks unfriendly interaction and unlocks cross-race trainers at exalted", %{id: id} do
      catalog = catalog([definition(72, 19)])
      character = state(id, catalog).character
      trainer_guid = vendor_guid(72)
      ReputationLoader.put_catalog(catalog)

      assert Reputation.can_interact?(character, trainer_guid)
      refute Reputation.exalted_with?(character, trainer_guid)

      character = put_standing(character, catalog, 72, -3_000)

      refute Reputation.can_interact?(character, trainer_guid)
      refute Reputation.exalted_with?(character, trainer_guid)

      character = put_standing(character, catalog, 72, 42_000)

      assert Reputation.can_interact?(character, trainer_guid)
      assert Reputation.exalted_with?(character, trainer_guid)
    end
  end

  describe "item_requirement_met?/3" do
    test "checks explicit item factions and vendor-faction fallbacks", %{id: id} do
      catalog = catalog([definition(72, 19), definition(529, 13)])
      character = state(id, catalog).character
      vendor_guid = vendor_guid(72)
      ReputationLoader.put_catalog(catalog)

      explicit = %ItemTemplate{required_reputation_faction: 529, required_reputation_rank: 4}
      implicit = %ItemTemplate{required_reputation_rank: 4}

      refute Reputation.item_requirement_met?(character, vendor_guid, explicit)
      refute Reputation.item_requirement_met?(character, vendor_guid, implicit)

      assert Reputation.validate_item_requirement(character, explicit) ==
               {:error, :cant_equip_reputation}

      character =
        character
        |> put_standing(catalog, 529, 3_000)
        |> put_standing(catalog, 72, 3_000)

      assert Reputation.item_requirement_met?(character, vendor_guid, explicit)
      assert Reputation.item_requirement_met?(character, vendor_guid, implicit)
      assert Reputation.validate_item_requirement(character, explicit) == :ok
    end
  end

  describe "vendor_items/3" do
    test "shows explicit requirements, hides unmet vendor requirements, and prices the result", %{id: id} do
      catalog = catalog([definition(72, 19), definition(529, 13)])
      character = state(id, catalog).character |> put_standing(catalog, 72, 9_000)
      vendor_guid = vendor_guid(72)
      ReputationLoader.put_catalog(catalog)

      explicit = %ItemTemplate{
        entry: 1,
        buy_price: 25,
        required_reputation_faction: 529,
        required_reputation_rank: 4
      }

      implicit = %ItemTemplate{entry: 2, buy_price: 25, required_reputation_rank: 6}
      unrestricted = %ItemTemplate{entry: 3, buy_price: 25}

      items =
        Reputation.vendor_items(character, vendor_guid, [
          %{index: 1, template: explicit, max_count: 0},
          %{index: 2, template: implicit, max_count: 0},
          %{index: 3, template: unrestricted, max_count: 0}
        ])

      assert Enum.map(items, &{&1.index, &1.template.entry, &1.price}) == [
               {1, 1, 23},
               {2, 3, 23}
             ]
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
      catalog = catalog([])
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

  defp put_standing(%Character{} = character, catalog, faction_id, standing) do
    {reputation, _changes} =
      ReputationLogic.set(character.player.reputation, catalog, faction_id, standing, context())

    %{character | player: %{character.player | reputation: reputation}}
  end

  defp vendor_guid(faction_id) do
    guid = Guid.from_low_guid(:mob, faction_id, System.unique_integer([:positive, :monotonic]))
    Metadata.put(guid, %{faction_template: %FactionTemplate{faction: faction_id}})
    on_exit(fn -> Metadata.delete(guid) end)
    guid
  end

  defp context, do: %{race: 1, class: 1}
end
