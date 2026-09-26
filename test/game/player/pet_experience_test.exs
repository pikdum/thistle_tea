defmodule ThistleTea.Game.Player.PetExperienceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.DamageOrigin
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.PetProgressChanged
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.SmsgPetNameQueryResponse
  alias ThistleTea.Game.Network.Message.SmsgPetSpells
  alias ThistleTea.Game.Player.CompanionVisibility
  alias ThistleTea.Game.Player.PetExperience
  alias ThistleTea.Game.Player.Pets
  alias ThistleTea.Game.World.Loader.PetLevel, as: PetLevelLoader
  alias ThistleTea.Test.PetControlOwner

  setup [:build_reward_context]

  describe "reward_kill/4" do
    test "routes solo XP to the active pet using creature reward modifiers", %{character: character, victim: victim} do
      PetExperience.reward_kill(character, victim, 295, :solo)
      assert_receive {:reward_pet_kill, 1, 60, {:solo, 50, opts}}

      assert opts == [
               non_raid_dungeon?: false,
               experience_multiplier: 1.0,
               damage_multiplier: 0.5,
               no_xp?: false,
               elite?: false
             ]
    end

    test "forwards the group share without rested XP", %{character: character, victim: victim} do
      character = %{character | internal: %{character.internal | rest_bonus: 10_000.0}}
      PetExperience.reward_kill(character, victim, 137, {:group, 60})
      assert_receive {:reward_pet_kill, 1, 60, {:group, 137, 60}}
    end

    test "ignores grey kills, dead owners, suspended pets and controlled victims", %{
      character: character,
      victim: victim
    } do
      PetExperience.reward_kill(character, victim, 0, :solo)
      PetExperience.reward_kill(%{character | unit: %{character.unit | health: 0}}, victim, 100, {:group, 60})
      PetExperience.reward_kill(%{character | player: %Player{flags: 0x10}}, victim, 100, {:group, 60})
      PetExperience.reward_kill(Companion.suspend(character), victim, 100, :solo)
      PetExperience.reward_kill(character, %{victim | internal: %{victim.internal | pet: %Pet{}}}, 100, :solo)
      refute_receive {:reward_pet_kill, _, _, _}
    end
  end

  describe "pet reward delivery" do
    test "updates the pet and retains its progress through the typed owner notification", %{
      character: character,
      pet: pet
    } do
      reward = {:reward_pet_kill, 1, 60, {:group, 137, 60}}
      assert {:noreply, updated, {:continue, :maybe_broadcast}} = MobServer.handle_info(reward, pet)
      assert updated.unit.pet_experience == 137
      assert updated.internal.broadcast_update?
      Entity.register(1)
      EventSink.emit_pending(updated)
      assert_receive %PetProgressChanged{progress: %PetProgress{level: 50, xp: 137}} = effect
      assert {:noreply, state} = PlayerServer.handle_info(effect, %State{character: character})
      assert Companion.relationship(state.character).progress.xp == 137
    end

    test "rejects a different owner and stops granting experience after pet death", %{pet: pet} do
      assert {:noreply, ^pet} = MobServer.handle_info({:reward_pet_kill, 9, 60, {:group, 137, 60}}, pet)
      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert {:noreply, ^dead, _} = MobServer.handle_info({:reward_pet_kill, 1, 60, {:group, 137, 60}}, dead)
    end
  end

  describe "taming" do
    test "forwards the wild creature's level to its new owner", %{pet: pet} do
      Entity.register(1)
      pet = %{pet | object: %{pet.object | guid: Guid.runtime(:mob, 2960)}, unit: %{pet.unit | level: 8}}
      EventSink.emit(pet, Effects.tame_creature(1, 2960))
      assert_receive {:tame_pet, 2960, 8}
    end
  end

  describe "companion restoration" do
    test "publishes the current name after a query for the previous pet was lost during loading", %{
      character: character,
      pet: pet
    } do
      number = Companion.relationship(character).pet_number
      state = %State{ready: false, character: character}
      assert Pets.query(state, pet.object.guid + 1, number) == state
      refute_receive {:"$gen_cast", {:send_packet, %SmsgPetNameQueryResponse{}}}

      pet = %{
        pet
        | unit: %{pet.unit | pet_number: number, pet_name_timestamp: 123},
          internal: %{pet.internal | name: "Boar"}
      }

      assert {:noreply, ^pet} = MobServer.handle_info({:attach_pet, self(), 1515, []}, pet)
      assert_receive %Attachment{} = attachment
      pet_pid = start_supervised!({PetControlOwner, control: pet.internal.pet})
      attachment = %{attachment | pid: pet_pid}
      ready = %{state | ready: true, guid: character.object.guid}
      completed = CompanionVisibility.finish_attachment(ready, attachment)
      assert map_size(completed.character.internal.companion.action_bar) == 10
      assert_receive {:"$gen_cast", {:send_packet, first}}
      assert %SmsgPetSpells{} = first
      assert_receive {:"$gen_cast", {:send_packet, second}}
      assert %SmsgPetNameQueryResponse{pet_number: ^number, name: "Boar", timestamp: 123} = second
    end

    test "projects the restored pet stance on the client pet bar", %{character: character, pet: pet} do
      character = Companion.capture_reaction(character, :passive)
      entity_ref = Companion.active_ref(character)
      control = %{pet.internal.pet | reaction_state: :passive}
      pet_pid = start_supervised!({PetControlOwner, control: control})
      attachment = %Attachment{kind: :hunter_pet, entity_ref: entity_ref, pid: pet_pid, spells: []}
      state = %State{character: character, guid: character.object.guid}
      completed = CompanionVisibility.finish_attachment(state, attachment)
      assert completed.character.internal.companion.reaction_state == :passive
      assert_receive {:"$gen_cast", {:send_packet, %SmsgPetSpells{reaction_state: 0}}}
    end
  end

  defp build_reward_context(_context) do
    guid = Guid.from_low_guid(:pet, 2960, :erlang.unique_integer([:positive]))
    Entity.register(guid)

    character =
      %Character{object: %Object{guid: 1}, unit: %Unit{health: 100, level: 60}, internal: %Internal{}}
      |> Companion.activate(:hunter_pet, %EntityRef{guid: guid, entry: 2960, spell_id: 1515})

    victim = %Mob{
      unit: %Unit{level: 50},
      internal: %Internal{
        creature: %Creature{experience_multiplier: 1.0, extra_flags: 0, rank: 0},
        damage_origin: %DamageOrigin{player: 50, npc: 50}
      }
    }

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 50, health: 100, pet_experience: 0, pet_loyalty: 1},
      internal: %Internal{pet: %Pet{kind: :hunter, owner_guid: 1}}
    }

    previous = PetLevelLoader.levels()

    stats = %PetLevel{
      level: 50,
      health: 2_215,
      armor: 3_018,
      strength: 113,
      agility: 82,
      stamina: 207,
      intellect: 43,
      spirit: 67,
      next_level_xp: 36_875
    }

    :ets.insert(PetLevelLoader, {:levels, %{50 => stats}})
    on_exit(fn -> :ets.insert(PetLevelLoader, {:levels, previous}) end)
    %{character: character, victim: victim, pet: pet}
  end
end
