defmodule ThistleTea.Game.Entity.Server.GuardianOwnerTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Guardians
  alias ThistleTea.Game.Entity.Server.GuardianOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Guardian, as: GuardianLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @entries [990_201, 990_202]

  setup [:templates, :owner]

  describe "summon/3" do
    test "multiple guardians coexist and direct casts toggle only their entry", %{owner: owner} do
      {active, monitors} = GuardianOwner.summon(owner, %{}, %{request() | count: 2})
      first = Guardians.active(active)
      assert length(first) == 2
      assert map_size(monitors) == 2
      old_token = monitors |> Map.keys() |> hd()
      angles = Enum.map(first, &:sys.get_state(Entity.pid(&1.guid)).internal.pet.follow_angle)
      assert length(Enum.uniq(angles)) == 2
      {active, monitors} = GuardianOwner.summon(active, monitors, %{request() | entry: 990_202})
      assert length(Guardians.active(active)) == 3
      {active, monitors} = GuardianOwner.summon(active, monitors, request())
      assert [%{entry: 990_202}] = Guardians.active(active)
      assert map_size(monitors) == 1
      Enum.each(first, &assert_removed(&1.guid))

      assert GuardianOwner.process_down(active, monitors, old_token) == {active, monitors}

      GuardianOwner.dismiss(active, monitors)
    end

    test "triggered summons accumulate and categorized casts replace", %{owner: owner} do
      {active, monitors} = GuardianOwner.summon(owner, %{}, request())
      {active, monitors} = GuardianOwner.summon(active, monitors, %{request() | triggered?: true})
      assert length(Guardians.active(active)) == 2
      previous = Guardians.active(active)
      {active, monitors} = GuardianOwner.summon(active, monitors, %{request() | replace?: true})
      assert length(Guardians.active(active)) == 1
      Enum.each(previous, &assert_removed(&1.guid))
      GuardianOwner.dismiss(active, monitors)
    end

    test "duration expiry clears its matching owner identity", %{owner: owner} do
      {active, monitors} = GuardianOwner.summon(owner, %{}, %{request() | duration_ms: 100})
      [{token, guid}] = Map.to_list(monitors)
      assert_receive {:DOWN, ^token, :process, _pid, _reason}, 1500
      {active, monitors} = GuardianOwner.process_down(active, monitors, token)
      assert active.internal.guardians == %{}
      assert monitors == %{}
      assert_removed(guid)
    end

    test "world transitions remove every guardian", %{owner: owner} do
      {active, monitors} = GuardianOwner.summon(owner, %{}, %{request() | count: 2})
      refs = Guardians.active(active)
      state = %State{guid: owner.object.guid, character: active, guardian_monitors: monitors}
      state = State.prepare_worldport(state, WorldRef.open(1), owner.internal.world)
      assert state.character.internal.guardians == %{}
      assert state.guardian_monitors == %{}
      Enum.each(refs, &assert_removed(&1.guid))
    end

    test "creature owners spawn monitor and release their own guardians", %{owner: owner} do
      creature = Summon.build(990_202, owner.internal.world, owner.movement_block.position)
      {:ok, pid} = MobLoader.start_mob(creature)
      send(pid, request())
      state = :sys.get_state(pid)
      assert [ref] = Guardians.active(state)
      child = Entity.pid(ref.guid)
      token = Process.monitor(child)
      assert :sys.get_state(child).internal.pet.owner_guid == creature.object.guid
      assert World.stop_entity(pid) == :ok
      assert_receive {:DOWN, ^token, :process, ^child, _reason}, 1500
      assert_removed(ref.guid)
    end
  end

  describe "GuardianLoader.build/5" do
    test "engineering trinkets scale statistics without changing template defaults", %{owner: owner} do
      now = Time.now()
      position = owner.movement_block.position
      unscaled = GuardianLoader.build(owner, request(), position, now)
      assert unscaled.unit.level == 20
      assert unscaled.unit.max_health == 1000

      item =
        ItemStore.create(%ItemTemplate{entry: 990_300, required_skill: 202, inventory_type: 12},
          owner: owner.object.guid
        )

      on_exit(fn -> ItemStore.delete(item.object.guid) end)
      skilled = %{owner | player: %{owner.player | skills: %{202 => %{value: 300}}}}
      scaled = GuardianLoader.build(skilled, %{request() | cast_item_guid: item.object.guid}, position, now)
      assert scaled.unit.level == 60
      assert scaled.unit.max_health == 3000
      assert scaled.unit.base_min_damage > unscaled.unit.base_min_damage
      assert scaled.unit.pet_number == 0
      assert scaled.unit.npc_flags == 2
      assert scaled.unit.summoned_by == owner.object.guid
      assert scaled.internal.loot == nil
      assert scaled.internal.pet.kind == :guardian
      assert scaled.internal.pet.reaction_state == :aggressive
      assert Summon.prototype(990_201).selected_level == 20
    end

    test "creature level offsets honor template overrides and valid level bounds", %{owner: owner} do
      creature = Summon.build(990_202, owner.internal.world, owner.movement_block.position)
      creature = %{creature | unit: %{creature.unit | level: 60}}
      position = creature.movement_block.position
      now = Time.now()
      assert GuardianLoader.build(creature, request(), position, now).unit.level == 60
      assert GuardianLoader.build(creature, %{request() | level_offset: -5.0}, position, now).unit.level == 55
      assert GuardianLoader.build(creature, %{request() | level_offset: 1.0}, position, now).unit.level == 20
      assert GuardianLoader.build(creature, %{request() | level_offset: -60.0}, position, now).unit.level == 20
    end
  end

  defp request, do: %Effects.SummonGuardians{entry: 990_201, spell_id: 500, count: 1, duration_ms: 0}

  defp assert_removed(guid) do
    refute Entity.online?(guid)
    assert World.position(guid) == nil
    assert Metadata.query(guid, [:alive?]) == nil
  end

  defp owner(_context) do
    guid = System.unique_integer([:positive]) + 20_000_000
    Entity.register(guid)

    owner = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 100, max_health: 100, faction_template: 1, flags: 8},
      player: %Player{flags: 0},
      internal: %Internal{world: WorldRef.open(998)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    World.update_position(owner)
    Metadata.put(guid, %{alive?: true, orientation: 0.0, pvp?: false})

    on_exit(fn ->
      Enum.each(World.guids(owner.internal.world), &World.stop_entity/1)
      World.remove_position(owner)
      Metadata.delete(guid)
    end)

    %{owner: owner}
  end

  defp templates(_context) do
    for level <- [20, 55, 60] do
      stats = %Mangos.CreatureClassLevelStats{
        class: 1,
        level: level,
        health: level * 25,
        mana: level,
        melee_damage: level * 2.0,
        ranged_damage: 0.0,
        armor: level * 10,
        strength: level,
        agility: level,
        stamina: level,
        intellect: level,
        spirit: level,
        attack_power: level * 2,
        ranged_attack_power: 0
      }

      :ets.insert(Summon, {{:class_level_stats, 1, level}, stats})
    end

    for entry <- @entries do
      [{_, stats}] = :ets.lookup(Summon, {:class_level_stats, 1, 20})

      creature = %Mangos.Creature{
        guid: 1,
        id: entry,
        modelid: 1,
        selected_level: 20,
        creature_class_level_stats: stats,
        creature_movement: [],
        creature_template: %Mangos.CreatureTemplate{
          entry: entry,
          name: "Test Guardian",
          unit_class: 1,
          min_level: 20,
          max_level: 20,
          scale: 1.0,
          health_multiplier: 2.0,
          faction_alliance: 1,
          npc_flags: 2
        }
      }

      :ets.insert(Summon, {entry, creature})
    end

    on_exit(fn ->
      Enum.each(@entries, &:ets.delete(Summon, &1))
      Enum.each([20, 55, 60], &:ets.delete(Summon, {:class_level_stats, 1, &1}))
    end)

    :ok
  end
end
