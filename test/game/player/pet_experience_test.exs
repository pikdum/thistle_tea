defmodule ThistleTea.Game.Player.PetExperienceTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.PetLevel
  alias ThistleTea.Game.Entity.Data.PetProgress
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects.PetProgressChanged
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Player.PetExperience
  alias ThistleTea.Game.World.Loader.PetLevel, as: PetLevelLoader

  setup [:build_reward_context]

  describe "reward_kill/4" do
    test "routes solo XP to the active pet using creature reward modifiers", %{character: character, victim: victim} do
      PetExperience.reward_kill(character, victim, 295, :solo)
      assert_receive {:reward_pet_kill, 1, 60, {:solo, 50, opts}}
      assert opts == [experience_multiplier: 1.0, extra_flags: 0, elite?: false]
    end

    test "forwards the group share without rested XP", %{character: character, victim: victim} do
      character = %{character | internal: %{character.internal | rest_bonus: 10_000.0}}
      PetExperience.reward_kill(character, victim, 137, :group)
      assert_receive {:reward_pet_kill, 1, 60, {:group, 137}}
    end

    test "ignores grey kills, dead owners, suspended pets and controlled victims", %{
      character: character,
      victim: victim
    } do
      PetExperience.reward_kill(character, victim, 0, :solo)
      PetExperience.reward_kill(%{character | unit: %{character.unit | health: 0}}, victim, 100, :group)
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
      reward = {:reward_pet_kill, 1, 60, {:group, 137}}
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
      assert {:noreply, ^pet} = MobServer.handle_info({:reward_pet_kill, 9, 60, {:group, 137}}, pet)
      dead = %{pet | unit: %{pet.unit | health: 0}}
      assert {:noreply, ^dead, _} = MobServer.handle_info({:reward_pet_kill, 1, 60, {:group, 137}}, dead)
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
      internal: %Internal{creature: %Creature{experience_multiplier: 1.0, extra_flags: 0, rank: 0}}
    }

    pet = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{level: 50, health: 100, pet_experience: 0},
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
