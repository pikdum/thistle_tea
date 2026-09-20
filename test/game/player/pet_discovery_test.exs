defmodule ThistleTea.Game.Player.PetDiscoveryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.PetTraining
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.PetSpells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  setup [:build_owner]

  describe "discover/2" do
    @tag :dbc_db
    test "learns the recipe once, not the pet attack, and retains it after dismissal", %{state: state, event: event} do
      assert {:noreply, learned} = PlayerServer.handle_info(event, state)
      assert learned.character.internal.spells == [7370]
      assert Map.has_key?(learned.character.internal.spellbook, 7370)
      refute Map.has_key?(learned.character.internal.spellbook, 7371)
      assert CharacterStore.get(state.guid).internal.spells == [7370]
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLearnedSpell{spell_id: 7370}}}

      assert PetTraining.discover(learned, event) == learned
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgLearnedSpell{}}}
      dismissed = %{learned | character: Companion.suspend(learned.character)}
      assert dismissed.character.internal.spells == [7370]
      assert PetTraining.discover(dismissed, event) == dismissed
    end

    test "ignores stale pets and another owner's event", %{state: state, event: event} do
      assert PetTraining.discover(state, %{event | source_guid: event.source_guid + 1}) == state
      assert PetTraining.discover(state, %{event | target_guid: state.guid + 1}) == state
      assert PetTraining.discover(%State{}, event) == %State{}
    end
  end

  describe "discover_passives/2" do
    @tag :dbc_db
    test "learns innate passive recipes on attachment without teaching active recipes", %{state: state} do
      previous = :ets.lookup(PetSpells, {:profile, 113})
      :ets.insert(PetSpells, {{:profile, 113}, %{recipes: %{4187 => 4195, 7371 => 7370}}})

      on_exit(fn ->
        :ets.delete(PetSpells, {:profile, 113})
        :ets.insert(PetSpells, previous)
      end)

      attachment = %Attachment{
        kind: :hunter_pet,
        entity_ref: %EntityRef{guid: Companion.summon_guid(state.character), entry: 113, spell_id: 1515},
        pid: self(),
        spells: Map.values(SpellLoader.build_spellbook([4187, 7371]))
      }

      learned = PetTraining.discover_passives(state, attachment)
      assert learned.character.internal.spells == [4195]
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgLearnedSpell{spell_id: 4195}}}
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgLearnedSpell{spell_id: 7370}}}
    end
  end

  defp build_owner(_context) do
    guid = System.unique_integer([:positive]) + 10_000_000
    on_exit(fn -> :ets.delete(CharacterStore, guid) end)
    pet = Guid.runtime(:pet, 113)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      unit: %Unit{race: 4, class: 3, level: 50, health: 100, auras: []},
      player: %Player{},
      internal: %Internal{spells: [], spellbook: %{}}
    }

    character = Companion.activate(character, :hunter_pet, %EntityRef{guid: pet, entry: 113, spell_id: 1515})
    event = %Effects.LearnPetRecipe{source_guid: pet, target_guid: guid, spell_id: 7370}
    %{state: %State{guid: guid, character: character}, event: event}
  end
end
