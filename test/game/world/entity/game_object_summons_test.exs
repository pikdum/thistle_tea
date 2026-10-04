defmodule ThistleTea.Game.World.Entity.GameObjectSummonsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity, as: EntityCore
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player, as: PlayerComponent
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Loot.Actor
  alias ThistleTea.Game.Core.Profession.OpenLock
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Entity.GameObjectSummons
  alias ThistleTea.Game.World.Entity.Mob.Corpse
  alias ThistleTea.Game.World.Entity.Player
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata

  setup [:templates]

  describe "prepare/2" do
    test "preserves zero coordinates and fills only unspecified values", %{caster: caster} do
      caster = %{caster | movement_block: %{caster.movement_block | position: {10.0, 20.0, 30.0, 1.0}}}

      for slot <- [nil, 1] do
        effect = Effects.summon_game_object(950_101, 60_000, slot: slot, position: {0.0, 0.0, 0.0, 0.0})
        assert GameObjectSummons.prepare(caster, effect).position == {0.0, 0.0, 0.0, 0.0}

        assert GameObjectSummons.prepare(caster, %{effect | position: {nil, 0.0, nil, nil}}).position ==
                 {10.0, 0.0, 30.0, 1.0}
      end
    end
  end

  describe "emit/3" do
    test "queues ownership work to the explicit owner with its source world", %{caster: caster} do
      owner = idle_owner()
      effect = Effects.summon_game_object(950_101, 60_000, slot: 1, position: {0.0, 0.0, 0.0, 0.0})
      EventSink.emit(caster, effect, Context.new(owner))
      send(owner, {:messages, self()})
      assert_receive {:messages, [%Effects.SummonGameObject{} = queued]}
      assert queued.world == caster.internal.world
      assert queued.position == {0.0, 0.0, 0.0, 0.0}
      assert World.nearby_game_objects(caster, 100) == []
    end
  end

  describe "summon/4" do
    test "replaces only the same owner's same slot and ignores stale removal", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      [{old_token, old}] = Map.to_list(monitors)
      monitors = summon(caster, monitors, 2)
      monitors = summon(caster, monitors, nil)
      other = %{caster | object: %Object{guid: 43}}
      [{_, other_object}] = Map.to_list(summon(other, %{}, 1))
      monitors = summon(caster, monitors, 1)

      assert map_size(monitors) == 3
      assert Entity.pid(old.guid) == nil
      assert World.position(old.guid) == nil
      assert Metadata.get(old.guid) == nil
      assert Process.alive?(other_object.pid)
      assert Enum.sort(Enum.map(Map.values(monitors), & &1.slot)) == [1, 2, nil]
      assert Enum.all?(Map.values(monitors), &Process.alive?(&1.pid))

      state = %State{character: caster, game_object_monitors: monitors}
      assert {:noreply, ^state} = Player.handle_info({:game_object_down, old_token, :process, old.pid, :normal}, state)
    end

    test "natural expiry removes projections and the owner's monitor record", %{caster: caster} do
      effect = request(caster, 1, 50)
      monitors = GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))
      [{token, entry}] = Map.to_list(monitors)
      assert_receive {:game_object_down, ^token, :process, pid, _reason} = down, 1_000
      assert pid == entry.pid
      assert Entity.pid(entry.guid) == nil
      assert World.position(entry.guid) == nil
      assert Metadata.get(entry.guid) == nil
      assert {:noreply, state} = Player.handle_info(down, %State{character: caster, game_object_monitors: monitors})
      assert state.game_object_monitors == %{}
    end

    test "disarming releases the owner's slot without activating the trap", %{caster: caster} do
      effect = %{request(caster, 1) | entry: 950_105}
      monitors = GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))
      [{token, entry}] = Map.to_list(monitors)
      actor = %Actor{guid: 43, group_id: nil, needed_items: MapSet.new(), distance: 4.0}
      assert Metadata.get(entry.guid).go_trap_stealthed?
      assert Metadata.get(entry.guid).owner_guid == caster.object.guid

      assert Entity.call(entry.guid, {:open_lock, actor, %OpenLock{lock_id: 12, lock_type: 4}, false}) ==
               {:ok, :disarmed, false}

      assert_receive {:game_object_down, ^token, :process, _, _} = down, 1_000
      assert Entity.pid(entry.guid) == nil
      assert World.position(entry.guid) == nil
      assert Metadata.get(entry.guid) == nil
      state = %State{character: caster, game_object_monitors: monitors}
      assert {:noreply, state} = Player.handle_info(down, state)
      assert state.game_object_monitors == %{}
      refute_receive {:receive_spell, _, _}
    end

    test "keeps objects on death and removes them when a creature's corpse leaves", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      [{_, entry}] = Map.to_list(monitors)
      dead = EntityCore.take_damage(caster, 100, 1_000)
      assert dead.unit.health == 0
      assert Process.alive?(entry.pid)

      mob = %Mob{
        object: caster.object,
        unit: dead.unit,
        internal: %{caster.internal | game_object_monitors: monitors},
        movement_block: caster.movement_block
      }

      ref = Process.monitor(entry.pid)
      removed = Corpse.remove(mob)
      assert removed.internal.game_object_monitors == %{}
      assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
    end

    test "releases linked objects on replacement", %{caster: caster} do
      effect = %{request(caster, 1) | entry: 950_102}
      monitors = GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))
      [{_, entry}] = Map.to_list(monitors)
      [linked_guid] = :sys.get_state(entry.pid).internal.summon.linked_guids
      linked_pid = Entity.pid(linked_guid)
      ref = Process.monitor(linked_pid)
      assert map_size(summon(caster, monitors, 1)) == 1
      assert_receive {:DOWN, ^ref, :process, ^linked_pid, _}, 1_000
      assert World.position(linked_guid) == nil
    end

    test "a departed owner removes its objects but leaves independent objects", %{caster: caster} do
      owner = idle_owner()
      [{token, entry}] = Map.to_list(GameObjectSummons.summon(caster, %{}, request(caster, 1), Context.new(owner)))
      wild = %{request(caster, nil) | owned?: false}
      {:ok, object, wild_pid} = GameObjectSummons.start(caster, wild, Context.new(owner))
      Process.exit(owner, :kill)
      replacement = idle_owner()
      assert Process.alive?(replacement)
      assert_receive {:game_object_down, ^token, :process, _, _}, 1_000
      assert World.position(entry.guid) == nil
      assert Process.alive?(wild_pid)
      assert World.position(object.object.guid) != nil
    end

    test "rejects a queued request from a previous world without replacing current objects", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      effect = %{request(caster, 1) | world: WorldRef.open(998)}
      assert GameObjectSummons.summon(caster, monitors, effect, Context.new(self())) == monitors
      assert Enum.all?(Map.values(monitors), &Process.alive?(&1.pid))
    end

    test "expiry releases a deferred cooldown with its original receipt", %{caster: caster} do
      spell = %Spell{id: 95_001, recovery_time_ms: 60_000, attributes: MapSet.new([:cooldown_on_event])}
      caster = Cooldowns.start(caster, spell, 100)
      effect = GameObjectSummons.prepare(caster, Effects.summon_game_object(950_101, 50, spell_id: spell.id))
      GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))
      assert_receive %Effects.ActivateCooldown{spell_id: 95_001, started_at: 100, cancel?: false}, 1_000
    end

    test "failed replacement clears its slot and cancels only the captured cooldown", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      [{_, old}] = Map.to_list(monitors)
      spell = %Spell{id: 95_001, recovery_time_ms: 60_000, attributes: MapSet.new([:cooldown_on_event])}
      caster = Cooldowns.start(caster, spell, 100)
      effect = GameObjectSummons.prepare(caster, Effects.summon_game_object(950_199, 50, slot: 1, spell_id: spell.id))
      caster = Cooldowns.start(caster, spell, 200)

      assert GameObjectSummons.summon(caster, monitors, effect, Context.new(self())) == %{}
      refute Process.alive?(old.pid)
      assert_receive %Effects.ActivateCooldown{started_at: 100, cancel?: true} = canceled
      assert Cooldowns.handle_event(caster, canceled, 300) == {caster, []}
      assert Cooldowns.pending(caster, spell.id).started_at == 200
    end
  end

  describe "handle_info/2" do
    test "player and creature owners retain separate monitor records", %{caster: caster} do
      effect = request(caster, 1)
      assert {:noreply, player} = Player.handle_info(effect, %State{character: caster})
      assert map_size(player.game_object_monitors) == 1

      mob = %Mob{
        object: %Object{guid: 43},
        unit: caster.unit,
        internal: caster.internal,
        movement_block: caster.movement_block
      }

      assert {:noreply, mob} = ThistleTea.Game.World.Entity.Mob.handle_info(effect, mob)
      assert map_size(mob.internal.game_object_monitors) == 1
      [player_object] = Map.values(player.game_object_monitors)
      [mob_object] = Map.values(mob.internal.game_object_monitors)
      assert player_object.guid != mob_object.guid
      assert :sys.get_state(player_object.pid).game_object.created_by == 42
      assert :sys.get_state(mob_object.pid).game_object.created_by == 43
    end

    test "an object keeps the objects its scripts raise and takes them when it goes", %{caster: caster} do
      {:ok, owner, owner_pid} =
        GameObjectSummons.start(caster, %{request(caster, nil) | owned?: false}, Context.new(self()))

      raise_post = Effects.summon_game_object(950_101, 60_000, position: {12.0, 22.0, 30.0, 0.0})
      send(owner_pid, GameObjectSummons.prepare(owner, raise_post))

      assert [%{pid: post_pid}] = Map.values(:sys.get_state(owner_pid).internal.game_object_monitors)
      assert :sys.get_state(post_pid).game_object.created_by == owner.object.guid

      ref = Process.monitor(post_pid)
      World.stop_entity(owner_pid)
      assert_receive {:DOWN, ^ref, :process, ^post_pid, _reason}, 1_000
    end
  end

  describe "player world departure" do
    test "logout saves an activated object cooldown", %{caster: caster} do
      caster = CharacterStore.create(caster)
      on_exit(fn -> :ets.delete(CharacterStore, caster.id) end)
      spell = %Spell{id: 95_001, recovery_time_ms: 60_000, attributes: MapSet.new([:cooldown_on_event])}
      caster = Cooldowns.start(caster, spell, 100)
      effect = GameObjectSummons.prepare(caster, Effects.summon_game_object(950_101, 60_000, spell_id: spell.id))
      monitors = GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))

      State.leave_world(%State{guid: caster.object.guid, character: caster, game_object_monitors: monitors})
      saved = CharacterStore.get(caster.id)
      assert Cooldowns.pending(saved, spell.id) == nil
      assert is_integer(Cooldowns.ready_at(saved, spell))
    end

    test "logout clears ownership and removes objects", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      [{_, entry}] = Map.to_list(monitors)
      ref = Process.monitor(entry.pid)
      assert %State{game_object_monitors: %{}} = State.leave_world(%State{game_object_monitors: monitors})
      assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
      assert World.position(entry.guid) == nil
    end

    test "world transfer clears ownership before arrival", %{caster: caster} do
      monitors = summon(caster, %{}, 1)
      [{_, entry}] = Map.to_list(monitors)
      ref = Process.monitor(entry.pid)
      state = %State{character: caster, game_object_monitors: monitors}
      transferred = State.prepare_worldport(state, caster.internal.world, WorldRef.open(998))
      assert transferred.game_object_monitors == %{}
      assert_receive {:DOWN, ^ref, :process, _, _}, 1_000
      assert World.position(entry.guid) == nil
    end
  end

  describe "dismiss/2" do
    test "uses the ritual's final completion state when releasing its cooldown", %{caster: caster} do
      spell = %Spell{id: 95_001, recovery_time_ms: 60_000, attributes: MapSet.new([:cooldown_on_event])}

      for completed? <- [false, true] do
        caster = Cooldowns.start(caster, spell, 100)
        effect = GameObjectSummons.prepare(caster, Effects.summon_game_object(950_104, 60_000, spell_id: spell.id))
        monitors = GameObjectSummons.summon(caster, %{}, effect, Context.new(self()))
        [{_, entry}] = Map.to_list(monitors)
        if completed?, do: GenServer.cast(entry.pid, {:gameobject_use, 43, 10})
        assert :sys.get_state(entry.pid).internal.ritual.completed? == completed?
        {released, remaining} = GameObjectSummons.dismiss(caster, monitors)
        assert remaining == %{}
        refute Process.alive?(entry.pid)
        assert Cooldowns.pending(released, spell.id) == nil
        assert is_integer(Cooldowns.ready_at(released, spell)) == completed?
      end
    end
  end

  defp summon(caster, monitors, slot),
    do: GameObjectSummons.summon(caster, monitors, request(caster, slot), Context.new(self()))

  defp request(caster, slot, duration \\ 60_000),
    do: GameObjectSummons.prepare(caster, Effects.summon_game_object(950_101, duration, slot: slot))

  defp idle_owner do
    pid = spawn(fn -> owner_loop([]) end)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    pid
  end

  defp owner_loop(messages) do
    receive do
      {:messages, caller} ->
        send(caller, {:messages, Enum.reverse(messages)})
        owner_loop([])

      message ->
        owner_loop([message | messages])
    end
  end

  defp templates(_context) do
    plain = %GameObjectTemplate{entry: 950_101, type: 5, size: 1.0, flags: 0, faction: 0}

    chest = %GameObjectTemplate{
      entry: 950_102,
      type: 3,
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [0, 0, 0, 1, 1, 1, 0, 950_103]
    }

    trap = %GameObjectTemplate{entry: 950_103, type: 6, size: 1.0, flags: 0, faction: 0, data: [0, 0, 0, 0, 1, 0, 0, 0]}
    ritual = %GameObjectTemplate{entry: 950_104, type: 18, size: 1.0, flags: 0, faction: 0, data: [2, 0, 0, 1]}
    hidden = %{trap | entry: 950_105, data: [12, 0, 0, 0, 1, 0, 0, 0, 0, 1]}
    for template <- [plain, chest, trap, ritual, hidden], do: GameObjectTemplateLoader.put(template)

    caster = %Character{
      object: %Object{guid: 42},
      player: %PlayerComponent{},
      unit: %Unit{health: 100, max_health: 100, level: 10, auras: []},
      internal: %Internal{world: WorldRef.open(999)},
      movement_block: %MovementBlock{position: {10.0, 20.0, 30.0, 1.0}}
    }

    on_exit(fn ->
      for {guid, _} <- World.nearby_game_objects(caster, 100), do: World.stop_entity(guid)
      for template <- [plain, chest, trap, ritual, hidden], do: :ets.delete(GameObjectTemplateLoader, template.entry)
      Metadata.delete(caster.object.guid)
    end)

    %{caster: caster}
  end
end
