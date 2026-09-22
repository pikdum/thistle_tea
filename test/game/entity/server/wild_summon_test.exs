defmodule ThistleTea.Game.Entity.Server.WildSummonTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Passive
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Summon
  alias ThistleTea.Game.World.Loader.WildSummon
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @entries [990_211, 990_212, 2673, 2674, 12_426]

  setup [:templates, :caster]

  describe "build/4" do
    test "ordinary summons keep their template faction level and independent lifetime", %{caster: caster} do
      mob = WildSummon.build(caster, request(), caster.movement_block.position, 1000)
      assert mob.unit.level == 20
      assert mob.unit.faction_template == 14
      assert mob.unit.summoned_by in [nil, 0]
      assert mob.unit.created_by in [nil, 0]
      assert mob.unit.created_by_spell == 500
      assert mob.internal.pet == nil
      assert mob.internal.spawn.temporary?
      assert mob.internal.spawn.death_at == nil
      assert mob.internal.spawn.despawn_type == 7
      assert mob.internal.loot.tapped_by == nil
    end

    test "creator loot claims salvage and honors no experience", %{caster: caster} do
      mob = WildSummon.build(caster, %{request() | entry: 990_212}, caster.movement_block.position, 1000)
      assert mob.unit.created_by == caster.object.guid
      assert mob.unit.summoned_by in [nil, 0]
      assert mob.internal.loot.tapped_by == %Tap{player: caster.object.guid}
      assert mob.internal.creature.experience_multiplier == 0.0
    end

    @tag :dbc_db
    test "all target dummies apply their passive and initial area taunt", %{caster: caster} do
      for {entry, passive, spawn} <- [{2673, 4044, 4507}, {2674, 4048, 4092}, {12_426, 19_809, 4092}] do
        mob = WildSummon.build(caster, %{request() | entry: entry}, caster.movement_block.position, 1000)
        assert mob.unit.faction_template == caster.unit.faction_template
        assert mob.unit.flags == 8
        assert mob.internal.creature.stationary?
        assert mob.internal.spawn.death_at == 16_000
        assert mob.internal.spawn.death_in_combat?
        assert Enum.any?(mob.unit.auras, &(&1.spell.id == passive))
        assert Enum.any?(mob.internal.events, &match?(%Effects.TriggerSpell{spell_id: ^spawn}, &1))
        mob = %{mob | internal: %{mob.internal | events: []}} |> BT.init(Passive.tree())
        {_, ticked} = BehaviorRunner.tick(Passive.tree(), mob, Context.new(4000))
        assert Enum.any?(ticked.internal.events, &is_struct(&1, Effects.TriggerSpell))
        {_, dead} = BehaviorRunner.tick(Passive.tree(), mob, Context.new(16_000))
        assert dead.unit.health == 0
        refute Enum.any?(dead.internal.events, &is_struct(&1, Effects.TriggerSpell))
      end
    end
  end

  describe "EventSink.emit/3" do
    test "repeated casts create independent actors without replacing companions", %{caster: caster} do
      effect = %{request() | count: 2}
      assert EventSink.emit(caster, effect) == caster
      assert EventSink.emit(caster, effect) == caster
      guids = World.guids(caster.internal.world) -- [caster.object.guid]
      assert length(guids) == 4
      World.remove_position(caster)
      Metadata.delete(caster.object.guid)
      Enum.each(guids, &assert(Entity.online?(&1)))
    end
  end

  describe "temporary corpse lifecycle" do
    test "expiry leaves a lootable corpse and removal stops every projection", %{caster: caster} do
      effect = %{request() | entry: 990_212, duration_ms: 100}
      mob = WildSummon.build(caster, effect, caster.movement_block.position, Time.now())
      {:ok, pid} = MobLoader.start_mob(mob)
      token = Process.monitor(pid)
      assert :sys.get_state(pid).unit.health > 0
      Process.sleep(250)
      dead = :sys.get_state(pid)
      assert dead.unit.health == 0
      assert dead.internal.death_finalized?
      assert dead.internal.spawn.respawn_ref == nil
      assert dead.internal.loot.tapped_by == %Tap{player: caster.object.guid}
      assert World.position(mob.object.guid) != nil
      send(pid, {:remove_corpse, make_ref()})
      refute :sys.get_state(pid).internal.loot.corpse_removed?
      send(pid, {:remove_corpse, dead.internal.loot.corpse_token})
      assert_receive {:DOWN, ^token, :process, ^pid, _reason}, 1000
      refute Entity.online?(mob.object.guid)
      assert World.position(mob.object.guid) == nil
      assert Metadata.get(mob.object.guid) == nil
    end
  end

  defp request do
    %Effects.SummonWild{entry: 990_211, spell_id: 500, count: 1, duration_ms: 0, position: {0.0, 0.0, 0.0, 0.0}}
  end

  defp caster(_context) do
    guid = System.unique_integer([:positive]) + 21_000_000
    Entity.register(guid)

    caster = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 60, health: 100, max_health: 100, faction_template: 1, flags: 8},
      player: %Player{flags: 0},
      internal: %Internal{world: WorldRef.open(997)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    World.update_position(caster)
    Metadata.put(guid, %{alive?: true, orientation: 0.0, pvp?: false})

    on_exit(fn ->
      Enum.each(World.guids(caster.internal.world), &World.stop_entity/1)
      World.remove_position(caster)
      Metadata.delete(guid)
    end)

    %{caster: caster}
  end

  defp templates(_context) do
    keys = [{:class_level_stats, 1, 20} | @entries]
    saved = Enum.flat_map(keys, &:ets.take(Summon, &1))

    for entry <- @entries do
      creature = %Mangos.Creature{
        guid: 1,
        id: entry,
        modelid: 1,
        selected_level: 20,
        creature_movement: [],
        creature_class_level_stats: %Mangos.CreatureClassLevelStats{
          class: 1,
          level: 20,
          health: 1000,
          mana: 0,
          melee_damage: 1.0,
          ranged_damage: 0.0,
          armor: 100,
          strength: 20,
          agility: 20,
          stamina: 20,
          intellect: 20,
          spirit: 20,
          attack_power: 0,
          ranged_attack_power: 0
        },
        creature_template: %Mangos.CreatureTemplate{
          entry: entry,
          name: "Test Wild Summon",
          unit_class: 1,
          min_level: 20,
          max_level: 20,
          scale: 1.0,
          faction_alliance: 14,
          creature_type_flags: if(entry == 990_211, do: 0, else: 0x2002)
        }
      }

      :ets.insert(Summon, {entry, creature})
      :ets.insert(Summon, {{:class_level_stats, 1, 20}, creature.creature_class_level_stats})
    end

    on_exit(fn ->
      Enum.each(keys, &:ets.delete(Summon, &1))
      :ets.insert(Summon, saved)
    end)

    :ok
  end
end
