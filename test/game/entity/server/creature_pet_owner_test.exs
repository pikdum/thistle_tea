defmodule ThistleTea.Game.Entity.Server.CreaturePetOwnerTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.CreatureSpell
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.CreaturePetOwner
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.CreaturePet
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @entries [990_301, 990_302]
  @levels [1, 18, 20]

  setup [:templates, :owner]

  describe "summon/2" do
    test "publishes one aggressive pet and rejects recasts while it lives", %{owner: owner, pid: pid} do
      {active, pet} = summon(pid, owner)
      guid = pet.object.guid
      assert active.unit.summon == guid
      assert Metadata.get(owner.object.guid).pet_guid == guid
      assert active.internal.guardians == %{}
      assert pet.internal.pet.kind == :creature_pet
      assert pet.internal.pet.reaction_state == :aggressive
      assert pet.internal.pet.owner_guid == owner.object.guid
      assert pet.unit.summoned_by == owner.object.guid
      assert Guid.high_guid(guid) == Guid.high_guid(:pet)
      assert pet.internal.loot == nil

      for entry <- @entries do
        send(pid, %{request(owner) | entry: entry})
        assert Companion.active_guid(:sys.get_state(pid)) == guid
      end

      send(Entity.pid(guid), :ai_tick)
      assert :sys.get_state(Entity.pid(guid)).object.guid == guid
      assert Mob.respawn(active).unit.summon == guid
    end

    test "replaces a dead pet only with the same entry and ignores its old monitor", %{owner: owner, pid: pid} do
      {active, pet} = summon(pid, owner)
      old = active.internal.companion_monitor
      kill(pet)
      assert Metadata.get(pet.object.guid).alive? == false
      assert Entity.online?(pet.object.guid)
      send(pid, %{request(owner) | entry: 990_302})
      assert Companion.active_guid(:sys.get_state(pid)) == pet.object.guid
      {replacement, next} = summon(pid, owner)
      assert next.object.guid != pet.object.guid
      assert_removed(pet.object.guid)
      send(pid, {:DOWN, old.token, :process, old.pid, :normal})
      assert :sys.get_state(pid).unit.summon == replacement.unit.summon
    end

    test "child termination clears the slot and all child projections", %{owner: owner, pid: pid} do
      {_active, pet} = summon(pid, owner)
      child = Entity.pid(pet.object.guid)
      token = Process.monitor(child)
      send(child, :pet_stop)
      assert_receive {:DOWN, ^token, :process, ^child, _reason}, 1500
      active = await_slot(pid, nil)
      assert active.unit.summon == 0
      assert active.internal.companion_monitor == nil
      assert Metadata.get(owner.object.guid).pet_guid == nil
      assert_removed(pet.object.guid)
    end

    test "owner termination releases its supervised child", %{owner: owner, pid: pid} do
      {_active, pet} = summon(pid, owner)
      child = Entity.pid(pet.object.guid)
      token = Process.monitor(child)
      assert World.stop_entity(pid) == :ok
      assert_receive {:DOWN, ^token, :process, ^child, _reason}, 1500
      assert_removed(pet.object.guid)
    end

    test "dead owners cannot summon queued pets", %{owner: owner} do
      dead = %{owner | unit: %{owner.unit | health: 0}}
      assert CreaturePetOwner.summon(dead, request(owner)) == dead
      assert CreaturePetOwner.summon(owner, %{request(owner) | source_guid: 1}) == owner
    end
  end

  describe "CreaturePet.build/2" do
    test "retains template casting delays and fills resources after pet passives", %{owner: owner} do
      passive = %Spell{
        id: 900_001,
        attributes: MapSet.new([:passive]),
        duration_ms: -1,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_increase_health, base_points: 100}]
      }

      active = %Spell{id: 900_002}
      template_spell = %CreatureSpell{spell_id: 900_003, delay_repeat_min_ms: 5000, delay_repeat_max_ms: 6000}
      prototype = Summon.prototype(990_301)
      prototype = %{prototype | spell_list: [template_spell], spellbook: %{900_003 => %Spell{id: 900_003}}}
      :ets.insert(Summon, {990_301, prototype})
      :ets.insert(Summon, {{:pet_spellbook, 990_301, 20}, %{active.id => active}})
      :ets.insert(Summon, {{:pet_passives, 990_301, 20}, [passive]})
      pet = CreaturePet.build(owner, request(owner))
      assert pet.unit.base_health == 1000
      assert pet.unit.health == 1100
      assert pet.unit.max_health == 1100
      assert [%{spell: %{id: 900_001}}] = pet.unit.auras
      assert [^template_spell, %CreatureSpell{spell_id: 900_002}] = pet.internal.creature.spells
      assert Map.keys(pet.internal.spellbook) |> Enum.sort() == [900_002, 900_003]
      assert pet.internal.pet.autocast == MapSet.new([900_002, 900_003])
    end

    test "scales from owner level with signed offsets and a level-one floor", %{owner: owner} do
      for {offset, level} <- [{0.0, 20}, {-2.9, 18}, {-99.0, 1}] do
        pet = CreaturePet.build(owner, %{request(owner) | level_offset: offset})
        assert pet.unit.level == level
        assert pet.unit.base_health == level * 50
        assert pet.unit.health == pet.unit.max_health
        assert pet.unit.power1 == pet.unit.max_power1
        assert pet.unit.base_normal_resistance == level * 10
        assert pet.unit.npc_flags == 0
        assert pet.unit.faction_template == owner.unit.faction_template
      end
    end

    test "pet level rows override canonical inputs while zero damage and armor retain template values", %{owner: owner} do
      base = CreaturePet.build(owner, request(owner))

      stats = %Mangos.PetLevelStats{
        entry: 990_301,
        level: 20,
        health: 333,
        mana: 44,
        armor: 0,
        dmg_min: 0.0,
        dmg_max: 0.0,
        strength: 10,
        agility: 11,
        stamina: 12,
        intellect: 13,
        spirit: 14
      }

      :ets.insert(Summon, {{:pet_stats, 990_301, 20}, stats})
      pet = CreaturePet.build(owner, request(owner))
      assert pet.unit.base_health == 333
      assert pet.unit.health == 333
      assert pet.unit.power1 == 44
      assert pet.unit.base_strength == 10
      assert pet.unit.base_normal_resistance == base.unit.base_normal_resistance
      assert pet.unit.base_min_damage == base.unit.base_min_damage
      :ets.insert(Summon, {{:pet_stats, 990_301, 20}, %{stats | armor: 50, dmg_min: 7.0, dmg_max: 9.0}})
      pet = CreaturePet.build(owner, request(owner))
      assert pet.unit.base_normal_resistance == 50
      assert pet.unit.base_min_damage == 7.0
      assert pet.unit.base_max_damage == 9.0
    end
  end

  defp summon(pid, owner) do
    send(pid, request(owner))
    active = :sys.get_state(pid)
    {active, :sys.get_state(Entity.pid(Companion.active_guid(active)))}
  end

  defp request(owner), do: %Effects.SummonPet{source_guid: owner.object.guid, entry: 990_301, spell_id: 8722}

  defp kill(pet) do
    spell = %Spell{id: 5, effects: [%Effect{index: 0, type: :instakill}]}
    Entity.receive_spell(pet.object.guid, %CastContext{caster_guid: pet.object.guid, caster_level: 20}, spell)
    assert :sys.get_state(Entity.pid(pet.object.guid)).unit.health == 0
  end

  defp await_slot(pid, expected, attempts \\ 50) do
    state = :sys.get_state(pid)

    if Companion.active_guid(state) == expected or attempts == 0 do
      assert Companion.active_guid(state) == expected
      state
    else
      Process.sleep(10)
      await_slot(pid, expected, attempts - 1)
    end
  end

  defp assert_removed(guid) do
    refute Entity.online?(guid)
    assert World.position(guid) == nil
    assert Metadata.get(guid) == nil
  end

  defp owner(_context) do
    owner = Summon.build(990_302, WorldRef.open(997), {0.0, 0.0, 0.0, 0.0})
    {:ok, pid} = MobLoader.start_mob(owner)
    on_exit(fn -> Enum.each(World.guids(owner.internal.world), &World.stop_entity/1) end)
    %{owner: owner, pid: pid}
  end

  defp templates(_context) do
    keys = for level <- @levels, do: {:class_level_stats, 1, level}

    keys =
      keys ++
        @entries ++
        for(
          entry <- @entries,
          level <- @levels,
          kind <- [:pet_stats, :pet_spellbook, :pet_passives],
          do: {kind, entry, level}
        )

    previous = Enum.flat_map(keys, &:ets.lookup(Summon, &1))

    on_exit(fn ->
      Enum.each(keys, &:ets.delete(Summon, &1))
      :ets.insert(Summon, previous)
    end)

    for level <- @levels do
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
          name: "Test Creature Pet",
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

      for level <- @levels do
        :ets.insert(Summon, [
          {{:pet_stats, entry, level}, nil},
          {{:pet_spellbook, entry, level}, %{}},
          {{:pet_passives, entry, level}, []}
        ])
      end
    end

    :ok
  end
end
