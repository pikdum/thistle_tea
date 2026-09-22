defmodule ThistleTea.Game.Entity.Server.Player.MiniPetOwnerTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MiniPet
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Server.Player.MiniPetOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @entries [990_101, 990_102]

  setup [:templates, :owner]

  describe "summon/2" do
    @tag :dbc_db
    test "creation passives refresh the owner and expire after dismissal", %{state: state} do
      spell = SpellLoader.load(25_163)
      :ets.insert(Summon, {{:mini_pet_spells, 990_101}, %{25_163 => spell}})
      character = %{state.character | unit: %{state.character.unit | base_fire_resistance: 100, fire_resistance: 100}}
      active = MiniPetOwner.summon(%{state | character: character}, request(990_101))
      ref = MiniPet.active_ref(active.character)
      assert_receive {:"$gen_cast", {:receive_spell, %CastContext{} = context, ^spell}}, 1500
      assert context.caster_guid == ref.guid
      assert context.target_guid == state.guid
      now = Time.now()
      {affected, _events} = SpellEffect.receive(active.character, context, spell, now)
      assert affected.unit.fire_resistance == 80
      refute affected.internal.in_combat
      MiniPetOwner.dismiss(active)
      {restored, _events} = Aura.tick(affected, now + 3000)
      assert restored.unit.fire_resistance == 100
    end

    test "toggles and replaces critters without changing the combat slot", %{state: state} do
      state = MiniPetOwner.summon(state, request(990_101))
      first = MiniPet.active_ref(state.character)
      stale_token = state.mini_pet_monitor.token
      pet = :sys.get_state(Entity.pid(first.guid))
      assert pet.unit.level == 1
      assert pet.unit.npc_flags == 2
      assert pet.unit.pet_number == 0
      assert pet.unit.summoned_by == state.guid
      assert Bitwise.band(pet.unit.flags, 0x300) == 0x300
      assert pet.internal.pet.reaction_state == :passive
      assert pet.internal.loot == nil
      assert state.character.unit.summon == 88

      state = MiniPetOwner.summon(state, request(990_102))
      second = MiniPet.active_ref(state.character)
      refute Entity.online?(first.guid)
      assert World.position(first.guid) == nil
      assert Metadata.query(first.guid, [:alive?]) == nil
      assert second.entry == 990_102
      assert MiniPetOwner.process_down(state, stale_token) == state
      assert Companion.active_guid(state.character) == 88
      state = MiniPetOwner.summon(state, request(990_102))
      assert MiniPet.active_ref(state.character) == nil
      assert state.mini_pet_monitor == nil
      refute Entity.online?(second.guid)
      assert state.character.unit.summon == 88
    end

    test "timed expiry removes process and clears the matching owner slot", %{state: state} do
      state = MiniPetOwner.summon(state, %{request(990_101) | duration_ms: 100})
      ref = MiniPet.active_ref(state.character)
      token = state.mini_pet_monitor.token
      assert_receive {:DOWN, ^token, :process, _pid, _reason}, 1000
      state = MiniPetOwner.process_down(state, token)
      assert MiniPet.active_ref(state.character) == nil
      refute Entity.online?(ref.guid)
      assert World.position(ref.guid) == nil
    end

    test "death and world transitions tear down critters", %{state: state} do
      active = MiniPetOwner.summon(state, request(990_101))
      guid = MiniPet.active_ref(active.character).guid
      dead = Core.take_damage(active.character, 100, 1000, environmental?: true)
      state = MiniPetOwner.dismiss(%{active | character: dead})
      refute Entity.online?(guid)
      assert MiniPetOwner.summon(state, request(990_101)) == state

      alive = %{state | character: %{state.character | unit: %{state.character.unit | health: 100}}}
      active = MiniPetOwner.summon(alive, request(990_101))
      guid = MiniPet.active_ref(active.character).guid
      moved = State.prepare_worldport(active, WorldRef.open(1), active.character.internal.world)
      refute Entity.online?(guid)
      assert MiniPet.active_ref(moved.character) == nil
      assert moved.mini_pet_monitor == nil
    end

    test "missing owner presence tears down a live follower", %{state: state} do
      active = MiniPetOwner.summon(state, request(990_101))
      guid = MiniPet.active_ref(active.character).guid
      token = active.mini_pet_monitor.token
      World.remove_position(active.character)
      assert_receive {:DOWN, ^token, :process, _pid, _reason}, 1000
      refute Entity.online?(guid)
    end
  end

  defp request(entry), do: %Effects.SummonMiniPet{entry: entry, spell_id: 500, duration_ms: 0}

  defp owner(_context) do
    guid = System.unique_integer([:positive]) + 10_000_000
    Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      player: %Player{flags: 0},
      unit: %Unit{health: 100, max_health: 100, level: 60, faction_template: 1, auras: []},
      internal: %Internal{world: WorldRef.open(999)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    character = Companion.activate(character, :guardian, %EntityRef{guid: 88, entry: 416, spell_id: 688})
    World.update_position(character)
    Metadata.put(guid, %{alive?: true, orientation: 0.0})

    on_exit(fn ->
      World.remove_position(character)
      Metadata.delete(guid)
    end)

    %{state: %State{guid: guid, character: character, connection_pid: self()}}
  end

  defp templates(_context) do
    for entry <- @entries do
      creature = %Mangos.Creature{
        guid: 1,
        id: entry,
        modelid: 1,
        curhealth: 5,
        creature_movement: [],
        creature_template: %Mangos.CreatureTemplate{
          entry: entry,
          name: "Test Critter",
          min_level: 1,
          max_level: 1,
          scale: 1.0,
          speed_walk: 1.0,
          speed_run: 1.0,
          npc_flags: 2
        }
      }

      :ets.insert(Summon, [{entry, creature}, {{:mini_pet_spells, entry}, %{}}])
    end

    on_exit(fn ->
      for entry <- @entries do
        :ets.delete(Summon, entry)
        :ets.delete(Summon, {:mini_pet_spells, entry})
      end
    end)

    :ok
  end
end
