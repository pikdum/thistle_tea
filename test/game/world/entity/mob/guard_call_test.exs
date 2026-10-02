defmodule ThistleTea.Game.World.Entity.Mob.GuardCallTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Combat.FactionTemplate
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Mob.GuardCall
  alias ThistleTea.Game.World.Loader.BroadcastText, as: BroadcastTextLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @goldshire {12, 87}
  @elwynn {12, 12}
  @human_race 1
  @orc_race 2

  setup do
    previous = :ets.lookup(BroadcastTextLoader, 4403)
    :ets.insert(BroadcastTextLoader, {4403, %{text: "Guards! Help me!", chat_type: :say, language: 7, emote_id: 0}})

    on_exit(fn ->
      :ets.delete(BroadcastTextLoader, 4403)
      :ets.insert(BroadcastTextLoader, previous)
    end)

    %{civilian: civilian()}
  end

  describe "respond/3" do
    test "spends a post charge, shouts, and sends the civilian's guard", %{civilian: civilian} do
      enemy = put_player(@orc_race)
      parent = self()

      take = fn area ->
        send(parent, {:took, area})
        :ok
      end

      assert {{:summoned, 68}, [talk, summon]} =
               GuardCall.respond(civilian, enemy, zone_and_area: fn 0, _ -> @goldshire end, take: take, walk: &walk/3)

      assert_received {:took, 87}
      assert %Effects.MonsterTalk{text: "Guards! Help me!", chat_type: :say, target_guid: ^enemy} = talk

      assert %Effects.SummonCreature{
               target_guid: ^enemy,
               summon: %{entry: 68, despawn_type: 1, despawn_delay_ms: 120_000, attack_target: ^enemy}
             } = summon

      assert {5.0, +0.0, +0.0, _facing} = summon.summon.position
    end

    test "stays quiet while the post cools down", %{civilian: civilian} do
      enemy = put_player(@orc_race)

      assert GuardCall.respond(civilian, enemy, zone_and_area: fn _, _ -> @goldshire end, take: fn _ -> :denied end) ==
               {:denied, []}
    end

    test "only shouts when the post has no guard for the civilian's side", %{civilian: civilian} do
      enemy = put_player(@human_race)

      assert {:held, [%Effects.MonsterTalk{}]} =
               GuardCall.respond(civilian, enemy, zone_and_area: fn _, _ -> @goldshire end, take: fn _ -> :ok end)
    end

    test "rouses the nearest friendly guard outside a guarded town", %{civilian: civilian} do
      enemy = put_player(@orc_race)
      put_mob(Guid.from_low_guid(:mob, 2, Unique.integer()), {10.0, 0.0, 0.0}, guard?: true, faction: hostile())
      put_mob(Guid.from_low_guid(:mob, 3, Unique.integer()), {5.0, 0.0, 0.0}, guard?: false)
      guard = put_mob(Guid.from_low_guid(:mob, 4, Unique.integer()), {20.0, 0.0, 0.0}, guard?: true, register?: true)

      assert GuardCall.respond(civilian, enemy, zone_and_area: fn _, _ -> @elwynn end) == {:held, []}
      assert_received {:"$gen_cast", {:assist_attack, ^enemy}}
      assert Entity.pid(guard) == self()
    end
  end

  defp civilian do
    guid = Guid.from_low_guid(:mob, 1, Unique.integer())
    Metadata.put(guid, %{alive?: true, level: 10, unit_flags: 0, faction_template: stormwind()})
    on_exit(fn -> Metadata.delete(guid) end)

    %Mob{
      object: %Object{guid: guid, entry: 1},
      unit: %Unit{level: 10, health: 100, max_health: 100, faction_template: 12, display_id: 0},
      internal: %Internal{world: WorldRef.open(0), creature: %Creature{static_flags: 0x08000000, extra_flags: 0x2}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp put_player(race) do
    guid = Guid.from_low_guid(:player, Unique.integer())
    Metadata.put(guid, %{race: race, alive?: true})
    on_exit(fn -> Metadata.delete(guid) end)
    guid
  end

  defp put_mob(guid, {x, y, z}, opts) do
    if Keyword.get(opts, :register?, false), do: {:ok, _} = Entity.register(guid)
    SpatialHash.update(:mobs, guid, WorldRef.open(0), x, y, z)

    Metadata.put(guid, %{
      alive?: true,
      level: 10,
      unit_flags: 0,
      guard?: Keyword.fetch!(opts, :guard?),
      faction_template: Keyword.get(opts, :faction, stormwind())
    })

    on_exit(fn ->
      if Keyword.get(opts, :register?, false), do: Entity.unregister(guid)
      SpatialHash.remove(:mobs, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp walk(0, {+0.0, +0.0, +0.0}, {x, y, z}), do: {x, y, z}

  defp stormwind do
    %FactionTemplate{id: 12, faction: 72, flags: 0, faction_group: 2, friend_group: 2, enemy_group: 4}
  end

  defp hostile do
    %FactionTemplate{id: 17, faction: 15, flags: 1, faction_group: 8, friend_group: 0, enemy_group: 1, friends_0: 15}
  end
end
