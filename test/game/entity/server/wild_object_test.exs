defmodule ThistleTea.Game.Entity.Server.WildObjectTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Trap
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Server.GameObject.Chest
  alias ThistleTea.Game.Entity.Server.GameObject.Trap, as: TrapServer
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:templates]

  describe "emit/2" do
    test "publishes independent ownerless chests and removes linked objects with their parent", %{caster: caster} do
      effect = Effects.summon_game_object(950_001, 0, owned?: false, position: {0.0, 0.0, 0.0, 0.0})
      EventSink.emit(caster, effect)

      [{guid, _}] =
        World.nearby_game_objects(caster, 100) |> Enum.filter(fn {guid, _} -> Guid.entry(guid) == 950_001 end)

      pid = Entity.pid(guid)
      state = :sys.get_state(pid)
      assert state.game_object.created_by == nil
      assert state.game_object.level == 0
      assert state.internal.summon.owner_guid == nil
      assert World.position(guid) == {caster.internal.world, 0.0, 0.0, 0.0}
      assert %{db_guid: nil, go_spawned?: true} = Metadata.query(guid, [:db_guid, :go_spawned?])
      [linked_guid] = state.internal.summon.linked_guids
      linked_pid = Entity.pid(linked_guid)
      assert is_pid(linked_pid)
      ref = Process.monitor(linked_pid)
      World.stop_entity(pid)
      assert_receive {:DOWN, ^ref, :process, ^linked_pid, _}, 1_000
      assert World.position(guid) == nil
      assert World.position(linked_guid) == nil
      assert Metadata.query(guid, [:go_spawned?]) == nil
    end

    test "expires from the owner process without a summoner connection", %{caster: caster} do
      EventSink.emit(caster, Effects.summon_game_object(950_003, 100, owned?: false, position: {0.0, 0.0, 0.0, 0.0}))
      [{guid, _}] = World.nearby_game_objects(caster, 100)
      pid = Entity.pid(guid)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      assert World.position(guid) == nil
    end
  end

  describe "release/2" do
    test "consumed summoned chests disappear without scheduling a respawn", %{caster: caster} do
      template = TemplateLoader.cached(950_001)
      chest = GameObject.build_summoned(template, caster.internal.world, {0.0, 0.0, 0.0, 0.0})
      loot = %{chest.internal.loot | session: LootSession.new(%Loot{}, nil)}
      chest = %{chest | internal: %{chest.internal | loot: loot}}
      removed = Chest.release(chest, %Actor{guid: 42, group_id: nil, needed_items: MapSet.new(), distance: 0.0})
      assert removed.internal.loot.corpse_removed?
      assert_receive :despawn
      refute_receive :chest_respawn
    end
  end

  describe "consume/1" do
    test "finite charges deplete while zero charges repeat" do
      assert TrapServer.consume(%Trap{charges: 1}) == :depleted
      assert %Trap{charges: 1} = TrapServer.consume(%Trap{charges: 2})
      assert %Trap{charges: 0} = TrapServer.consume(%Trap{charges: 0})
    end
  end

  describe "ready?/2" do
    test "respects arming, cooldown and depletion" do
      refute TrapServer.ready?(%Trap{ready_at: 2_000}, 1_999)
      assert TrapServer.ready?(%Trap{ready_at: 2_000}, 2_000)
      refute TrapServer.ready?(%Trap{depleted?: true}, 5_000)
    end
  end

  defp templates(_context) do
    chest = %GameObjectTemplate{
      entry: 950_001,
      type: 3,
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [0, 10_100, 0, 1, 1, 1, 0, 950_002]
    }

    trap = %GameObjectTemplate{entry: 950_002, type: 6, size: 1.0, flags: 0, faction: 0, data: [0, 0, 0, 0, 1, 0, 0, 0]}
    plain = %GameObjectTemplate{entry: 950_003, type: 5, size: 1.0, flags: 0, faction: 0}
    for template <- [chest, trap, plain], do: :ets.insert(TemplateLoader, {template.entry, template})

    caster = %Character{
      object: %Object{guid: 42},
      unit: %Unit{level: 10},
      internal: %Internal{world: WorldRef.open(999)},
      movement_block: %MovementBlock{position: {10.0, 20.0, 30.0, 1.0}}
    }

    on_exit(fn ->
      Enum.each(World.nearby_game_objects(caster, 100), fn {guid, _} -> World.stop_entity(guid) end)
      for template <- [chest, trap, plain], do: :ets.delete(TemplateLoader, template.entry)
    end)

    %{caster: caster}
  end
end
