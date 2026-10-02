defmodule ThistleTea.Game.World.Entity.Mob.PetLifecycleTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Combat.Engagement
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.Internal.Spawn
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.PetAbility
  alias ThistleTea.Game.Core.Pet.PetLoyalty
  alias ThistleTea.Game.Core.Pet.PetProgress
  alias ThistleTea.Game.Core.Pet.PetResurrection
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Combat.ThreatSelection
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.Entity.Player, as: PlayerServer
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner
  alias ThistleTea.Game.World.Entity.Player.CompanionOwner.Attachment
  alias ThistleTea.Game.World.Entity.Player.PetTraining
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.PetTraining, as: PetTrainingLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.World.Spell.SpellRequirements
  alias ThistleTea.Game.World.Spell.SpellTargetResolver
  alias ThistleTea.Test.FactionFixtures
  alias ThistleTea.Test.Unique

  setup [{FactionFixtures, :seed}, :build_pet]

  describe "pet visibility" do
    test "sends the current name with a corpse reveal after an earlier query was lost", %{pet: pet} do
      pet = %{
        pet
        | unit: %{pet.unit | health: 0, pet_number: 77, pet_name_timestamp: 99},
          internal: %{pet.internal | name: "Briar"}
      }

      {:ok, pid} = World.start_entity(pet)
      parent = self()

      observer =
        spawn(fn ->
          for _ <- 1..2 do
            receive do
              packet -> send(parent, {:observer, packet})
            end
          end
        end)

      GenServer.cast(pid, {:send_update_to, observer})
      assert_receive {:observer, {:"$gen_cast", {:send_packet, %UpdateObject{update_type: :create_object2}}}}

      assert_receive {:observer,
                      {:"$gen_cast",
                       {:send_packet, %Message.SmsgPetNameQueryResponse{pet_number: 77, name: "Briar", timestamp: 99}}}}
    end
  end

  describe "resurrection lifecycle" do
    test "reviving a guardian removes sacrifice without reviving a different retained pet", %{pet: pet} do
      state = attach_owner(pet, self())
      guardian = %EntityRef{guid: pet.object.guid + 1, entry: 2675, spell_id: 4073}
      character = Companion.remember_death(state.character, pet.object.guid)
      character = %{character | internal: %{character.internal | guardians: %{guardian.guid => guardian}}}

      spell = %Spell{
        id: 18_789,
        duration_ms: 60_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :override_class_scripts, misc_value: 2228}]
      }

      {character, _events} = Aura.apply_spell(character, character.object.guid, 50, spell, 0)
      effect = %Effects.PetRevived{source_guid: guardian.guid, target_guid: state.guid, health: 70}

      assert {:noreply, updated, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info(effect, %{state | character: character})

      assert Companion.relationship(updated.character).dead?
      assert Companion.relationship(updated.character).health == 0
      refute Enum.any?(updated.character.unit.auras, &(&1.spell.id == 18_789))
    end

    test "publishes a retained corpse, revives the same process, and ignores stale expiry", %{pet: pet, guid: guid} do
      owner = attach_owner(pet, self()).character
      owner = %{owner | movement_block: pet.movement_block, unit: %{owner.unit | faction_template: 1}}
      Presence.enter(owner, %{alive?: true, faction_template: 1})
      on_exit(fn -> Presence.leave(owner) end)
      pet = %{pet | unit: %{pet.unit | faction_template: 1}}
      dead = EntityCore.kill(pet, ThistleTea.Game.Core.Time.now())
      {:ok, pid} = World.start_entity(dead)
      monitor = Process.monitor(pid)
      assert_receive %Effects.PetDied{}, 1_000
      corpse = :sys.get_state(pid)
      assert corpse.internal.death_finalized?
      generation = corpse.internal.pet.corpse_generation
      assert Metadata.query(guid, [:alive?, :pet_kind]) == %{alive?: false, pet_kind: :hunter}
      assert PetResurrection.corpse_delay(corpse) == 3_600_000

      spell = %Spell{
        id: 2006,
        range_yards: 30.0,
        effects: [%Effect{index: 0, type: :resurrect_new, base_points: 69, base_dice: 1, misc_value: 135}]
      }

      assert SpellTargetResolver.resolve(owner, spell, Target.unit(guid)) == [guid]
      old_spell = %{spell | effects: [%Effect{type: :resurrect}]}
      assert SpellTargetResolver.resolve(owner, old_spell, Target.unit(guid)) == []
      casting_spell = %{spell | cast_time_ms: 1_000, mana_cost: 10, power_type: 0}
      caster = %{owner | unit: %{owner.unit | power1: 80, max_power1: 100}}
      casting = Casting.start(caster, casting_spell, Target.unit(guid), 100)

      context = %CastContext{
        caster_guid: owner.object.guid,
        caster_level: 60,
        caster_position: {pet.internal.world, 2.0, 0.0, 0.0},
        caster_orientation: 0.0
      }

      Entity.receive_spell(guid, context, spell)
      assert_receive %Effects.PetRevived{source_guid: ^guid, health: 70} = revived, 1_000
      send(pid, {:pet_corpse_expired, generation})
      live = :sys.get_state(pid)
      assert live.unit.health == 70
      assert live.internal.blackboard.maintenance.next_regen_at > ThistleTea.Game.Core.Time.now()
      assert Metadata.query(guid, [:alive?]) == %{alive?: true}
      assert World.position(guid) == {pet.internal.world, 2.0, 0.0, 0.0}
      assert Entity.pid(guid) == pid
      assert SpellTargetResolver.resolve(owner, spell, Target.unit(guid)) == []
      pending = Casting.complete(casting, 1_100)
      cast = pending.internal.casting
      requirements = SpellRequirements.resolve(pending, cast.spell, cast.targets)
      aborted = Casting.resolve_requirements(pending, cast, requirements, 1_100)
      assert aborted.unit.power1 == 80
      assert Enum.any?(aborted.internal.events, &match?(%Effects.SpellCastFailed{reason: :target_not_dead}, &1))

      state = attach_owner(pet, pid)
      character = Companion.remember_death(state.character, guid)

      sacrifice = %Spell{
        id: 18_789,
        duration_ms: 60_000,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :override_class_scripts, misc_value: 2228}]
      }

      {character, _events} = Aura.apply_spell(character, character.object.guid, 50, sacrifice, 0)
      assert Enum.any?(character.unit.auras, &(&1.spell.id == 18_789))

      assert {:noreply, state, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_info(revived, %{state | character: character})

      refute Companion.relationship(state.character).dead?
      assert Companion.relationship(state.character).health == 70
      refute Enum.any?(state.character.unit.auras, &(&1.spell.id == 18_789))
      assert PlayerServer.handle_info(%{revived | source_guid: guid + 1}, state) == {:noreply, state}
      assert PlayerServer.handle_info(revived, %State{}) == {:noreply, %State{}}

      kill = %Spell{id: 5, effects: [%Effect{index: 0, type: :instakill}]}
      Entity.receive_spell(guid, context, kill)
      assert_receive %Effects.PetDied{}, 1_000
      corpse = :sys.get_state(pid)
      assert corpse.internal.pet.corpse_generation == generation + 1
      send(pid, {:pet_corpse_expired, generation})
      assert :sys.get_state(pid).unit.health == 0
      send(pid, {:pet_corpse_expired, generation + 1})
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 1_000
      assert Metadata.get(guid) == nil
      assert World.position(guid) == nil
    end
  end

  describe "taming lifecycle" do
    test "stops the wild creature without leaving threat or world projections", %{pet: pet, guid: guid, owner: owner} do
      wild = %{pet | internal: %{pet.internal | pet: nil}}
      wild = Engagement.enter(wild, owner, ThistleTea.Game.Core.Time.now(), ThreatSelection.opts(wild)).entity
      {:ok, pid} = World.start_entity(wild)
      ref = Process.monitor(pid)
      spell = %Spell{id: 13_481, effects: [%Effect{index: 0, type: :tame_creature}]}
      Entity.receive_spell(guid, %CastContext{caster_guid: owner, caster_level: 50}, spell)
      assert_receive {:tame_pet, 2960, 49}, 1_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1_000
      assert_receive {:"$gen_cast", {:threat_ref_lost, ^guid, _incarnation}}, 1_000
      refute Entity.online?(guid)
      assert Metadata.get(guid) == nil
      assert World.position(guid) == nil
    end
  end

  describe "pet training lifecycle" do
    setup [:training_catalogue]

    test "commits once, publishes ordered progress, and snapshots the purchase on suspension", %{
      pet: pet,
      guid: guid,
      teaching: teaching
    } do
      {:ok, pid} = World.start_entity(pet)
      state = attach_owner(pet, pid)
      effect = %Effects.LearnPetSpell{target_guid: guid, spell: teaching}
      assert :ok = PetTraining.validate(state.character, teaching)
      state = PetTraining.learn(state, effect)

      assert_receive %Effects.PetProgressChanged{source_guid: ^guid, progress: %{spells: [900], training_points: 0}} =
                       changed

      assert {:noreply, state} = PlayerServer.handle_info(changed, state)
      assert Companion.relationship(state.character).progress.spells == [900]
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: ^guid, spells: [_]}}}
      assert PetTraining.learn(state, effect) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x62}}}

      state = CompanionOwner.suspend(state)
      assert Companion.relationship(state.character).progress.spells == [900]
      assert PetTraining.validate(state.character, teaching) == {:error, :no_pet}
      refute Entity.online?(guid)
    end

    test "revalidates health at completion and ignores requests for a replaced pet", %{
      pet: pet,
      guid: guid,
      teaching: teaching
    } do
      state = attach_owner(pet, self())
      stale = %Effects.LearnPetSpell{target_guid: guid + 1, spell: teaching}
      assert PetTraining.learn(state, stale) == state
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x4C}}}

      dead = %{pet | unit: %{pet.unit | health: 0}}

      assert {:reply, {:error, :targets_dead}, ^dead} =
               MobServer.handle_call({:learn_pet_spell, state.guid, teaching}, nil, dead)

      assert {:reply, {:error, :no_pet}, ^pet} =
               MobServer.handle_call({:learn_pet_spell, state.guid + 1, teaching}, nil, pet)
    end

    test "delivers the purchase through the supplied owner context", %{pet: pet, teaching: teaching} do
      parent = self()
      receiver = spawn(fn -> receive do: (message -> send(parent, {:forwarded, message})) end)
      effect = %Effects.LearnPetSpell{target_guid: pet.object.guid, spell: teaching}
      EventSink.emit(pet, effect, Context.new(receiver))
      assert_receive {:forwarded, ^effect}
      refute_receive ^effect, 0
    end
  end

  describe "child_spec/1" do
    test "suspension snapshots final progress without restarting the supervised pet", %{pet: pet, guid: guid} do
      pet = PetLoyalty.initialize(pet, %PetProgress{level: 49, loyalty: 4, loyalty_points: 12_345, training_points: 45})
      {:ok, pid} = World.start_entity(pet)
      ref = Process.monitor(pid)

      assert {:ok, 166_500, false,
              %PetProgress{level: 49, xp: 123, loyalty: 4, loyalty_points: 12_345, training_points: 45}, :defensive,
              100} =
               Entity.call(guid, :suspend_hunter_pet)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert MobServer.child_spec(pet).restart == :temporary
      refute Entity.online?(guid)
    end
  end

  describe "broken loyalty lifecycle" do
    test "removes the retained bond, client controls, and supervised process", %{pet: pet, guid: guid, owner: owner} do
      {:ok, pid} = World.start_entity(pet)
      ref = Process.monitor(pid)
      state = attach_owner(pet, pid)
      broken = PetLoyalty.change(pet, -1_001)
      EventSink.emit_pending(broken, Context.new(pid))
      assert_receive %Effects.PetBroke{source_guid: ^guid, target_guid: ^owner} = effect

      assert {:noreply, detached, {:continue, :maybe_broadcast_update}} = PlayerServer.handle_info(effect, state)
      assert Companion.relationship(detached.character).status == :none
      assert detached.companion_monitor == nil
      assert detached.character.unit.summon == 0
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetBroken{}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgPetSpells{pet_guid: 0}}}
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
      refute Entity.online?(guid)
      assert PlayerServer.handle_info(effect, detached) == {:noreply, detached}
    end

    test "suspension racing a broken bond cannot retain or restore it", %{pet: pet, guid: guid} do
      broken = PetLoyalty.change(pet, -1_001)
      {:ok, pid} = World.start_entity(%{broken | internal: %{broken.internal | events: []}})
      state = attach_owner(pet, pid)
      suspended = CompanionOwner.suspend(state)
      assert Companion.relationship(suspended.character).status == :none
      assert suspended.companion_monitor == nil
      refute Entity.online?(guid)
    end

    test "uses the explicit entity context when its owner is absent", %{pet: pet, owner: owner} do
      Entity.unregister(owner)
      broken = PetLoyalty.change(pet, -1_001)
      parent = self()
      receiver = spawn(fn -> receive do: (message -> send(parent, {:forwarded, message})) end)
      EventSink.emit_pending(broken, Context.new(receiver))
      assert_receive {:forwarded, :pet_stop}
      refute_receive :pet_stop, 0
    end

    test "ignores notifications from replaced pets and after logout", %{pet: pet} do
      state = attach_owner(pet, self())
      effect = %Effects.PetBroke{source_guid: pet.object.guid + 1, target_guid: pet.internal.pet.owner_guid}
      assert PlayerServer.handle_info(effect, state) == {:noreply, state}
      assert PlayerServer.handle_info(effect, %State{}) == {:noreply, %State{}}
    end
  end

  defp attach_owner(pet, pid) do
    character = %Character{
      object: %Object{guid: pet.internal.pet.owner_guid},
      unit: %Unit{health: 100, auras: []},
      player: %Player{},
      internal: %Internal{world: pet.internal.world}
    }

    CompanionOwner.attach(%State{guid: character.object.guid, character: character}, %Attachment{
      kind: :hunter_pet,
      entity_ref: %EntityRef{guid: pet.object.guid, entry: 2960, spell_id: 1515},
      pid: pid,
      spells: []
    })
  end

  defp training_catalogue(%{pet: pet, owner: owner}) do
    character = %Character{
      object: %Object{guid: owner},
      unit: %Unit{health: 100},
      player: %Player{},
      internal: %Internal{world: pet.internal.world},
      movement_block: pet.movement_block
    }

    Presence.enter(character, %{alive?: true, faction_template: 1})
    on_exit(fn -> Presence.leave(character) end)
    previous = PetTrainingLoader.abilities()
    spell = %Spell{id: 900}
    :ets.insert(PetTrainingLoader, {:abilities, %{900 => %PetAbility{spell: spell, cost: 0, skills: [270]}}})
    on_exit(fn -> :ets.insert(PetTrainingLoader, {:abilities, previous}) end)
    %{teaching: %Spell{id: 901, effects: [%Effect{type: :learn_spell, implicit_target_a: :pet, trigger_spell_id: 900}]}}
  end

  defp build_pet(_context) do
    guid = Guid.runtime(:pet, 2960)
    owner = Unique.integer()
    {:ok, _} = Entity.register(owner)

    pet = %Mob{
      object: %Object{guid: guid, entry: 2960},
      unit: %Unit{
        health: 100,
        max_health: 100,
        level: 49,
        power5: 166_500,
        pet_experience: 123,
        pet_loyalty: 1,
        auras: []
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(451),
        pet: %Pet{owner_guid: owner, kind: :hunter, profile: :combat},
        creature: %Creature{},
        spawn: %Spawn{},
        spellbook: %{}
      }
    }

    on_exit(fn -> if Entity.online?(guid), do: World.stop_entity(guid) end)
    %{pet: pet, guid: guid, owner: owner}
  end
end
