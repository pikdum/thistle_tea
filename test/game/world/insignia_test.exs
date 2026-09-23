defmodule ThistleTea.Game.World.InsigniaTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Data.CorpseReclaim
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Insignia
  alias ThistleTea.Game.Entity.Logic.Loot
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Corpses
  alias ThistleTea.Game.Player.Insignia, as: PlayerInsignia
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.InsigniaTarget
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps

  setup [:bodies]

  describe "corpse claims" do
    test "only one competing claim creates bones, and money can be taken once", %{caster: caster, corpse: corpse} do
      guid = caster.object.guid

      calls =
        for _ <- 1..2, do: Task.async(fn -> Entity.call(corpse.object.guid, {:remove_insignia, guid, 300_000}) end)

      results = Enum.map(calls, &Task.await/1)
      assert [{:ok, bones}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert World.position(corpse.object.guid) == nil
      assert %{bones?: true, insignia: %{available?: false}} = Metadata.get(bones)
      assert {:error, _} = Entity.call(bones, {:remove_insignia, guid, 300_000})
      actor = %Actor{guid: guid, distance: 1.0, group_id: nil, needed_items: MapSet.new()}
      distant = %{actor | distance: 8.0}
      assert {:ok, %Loot{}} = Entity.call(bones, {:insignia_view, distant})
      assert {:error, :too_far} = Entity.call(bones, {:loot_view, distant})
      assert {:error, :too_far} = Entity.call(bones, {:loot_take_gold, distant})
      assert {:ok, %Loot{gold: gold}} = Entity.call(bones, {:loot_view, actor})
      assert gold in 280..840
      assert {:ok, ^gold} = Entity.call(bones, {:loot_take_gold, actor})
      assert {:error, :no_gold} = Entity.call(bones, {:loot_take_gold, actor})
      assert :sys.get_state(Entity.pid(bones)).corpse.dynamic_flags == 0
      assert {:error, :nothing_to_take} = Entity.call(bones, {:loot_view, actor})
    end

    test "rejects changed death identities, teammates, distant looters, and another copy", %{
      caster: caster,
      corpse: corpse
    } do
      guid = caster.object.guid
      assert {:error, :bad_targets} = Entity.call(corpse.object.guid, {:remove_insignia, guid, 1})
      Metadata.update(guid, %{insignia: %{team: :horde}})
      assert {:error, :target_friendly} = Entity.call(corpse.object.guid, {:remove_insignia, guid, 300_000})
      Metadata.update(guid, %{insignia: Insignia.projection(caster)})
      SpatialHash.update(:players, guid, caster.internal.world, 1100.0, 1200.0, -56.7)
      assert {:error, :out_of_range} = Entity.call(corpse.object.guid, {:remove_insignia, guid, 300_000})
      SpatialHash.update(:players, guid, WorldRef.instance(529, 9), 1165.0, 1200.0, -56.7)
      assert {:error, :bad_targets} = Entity.call(corpse.object.guid, {:remove_insignia, guid, 300_000})
      assert Entity.pid(corpse.object.guid)
    end

    test "released victims lose recovery while bones survive their next corpse", %{
      caster: caster,
      victim: victim,
      corpse: corpse
    } do
      {ghost, _events} = Death.release_spirit(victim, [], 100)
      state = %State{ready: true, guid: victim.object.guid, character: ghost}
      removed = PlayerInsignia.remove(state, caster.object.guid, 300_000)
      assert removed.character.internal.corpse_reclaim.released_at == nil
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgPlayerSkinned{spirit_released: false}}}
      assert_received {:"$gen_cast", {:send_packet, %Message.MsgCorpseQueryResponse{map: nil}}}
      assert_received {:"$gen_cast", {:insignia_loot, bones}}
      assert Corpses.reclaim(removed, 500_000) == removed
      assert {:ok, _pid} = World.start_entity(corpse)
      assert World.position(bones)
      assert World.position(corpse.object.guid)
      World.stop_entity(corpse.object.guid)
      assert World.position(bones)
      World.stop_world_entities(caster.internal.world)
      assert World.position(bones) == nil
    end

    test "offline owners remain removable and bones expire without restarting", %{
      caster: caster,
      victim: victim,
      corpse: corpse
    } do
      Metadata.delete(victim.object.guid)
      target = Target.corpse(corpse.object.guid, victim.object.guid, :enemy)
      info = InsigniaTarget.info(caster, target)
      assert Insignia.validate(caster, info) == :ok
      state = %State{guid: caster.object.guid, character: caster}
      assert PlayerInsignia.complete(state, target, 22_027) == state
      assert_received {:"$gen_cast", {:insignia_loot, bones}}
      pid = Entity.pid(bones)
      monitor = Process.monitor(pid)
      send(pid, :expire)
      assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
      assert Entity.pid(bones) == nil
      assert World.position(bones) == nil
    end
  end

  describe "cast launch" do
    test "sends removal to the explicit owner context without delivering a unit spell to the corpse", %{
      caster: caster,
      victim: victim,
      corpse: corpse
    } do
      spell = %Spell{
        id: 22_027,
        name: "Remove Insignia",
        cast_time_ms: 0,
        dmg_class: 0,
        range_yards: 5.0,
        power_type: 0,
        mana_cost: 0,
        effects: [%Effect{type: :remove_insignia}]
      }

      target = Target.corpse(corpse.object.guid, victim.object.guid, :enemy)
      complete = caster |> Casting.start(spell, target, 1_000) |> Casting.complete(1_000)
      assert complete.internal.casting == nil
      assert Enum.any?(complete.internal.events, &match?(%Effects.RemoveInsignia{targets: ^target}, &1))
      refute Enum.any?(complete.internal.events, &match?(%Effects.DeliverSpell{}, &1))
      EventSink.emit_pending(complete, Context.new(self()))
      assert_received {:remove_insignia, ^target, 22_027}

      World.stop_entity(corpse.object.guid)
      failed = caster |> Casting.start(spell, target, 2_000) |> Casting.complete(2_000)
      refute Enum.any?(failed.internal.events, &match?(%Effects.RemoveInsignia{}, &1))
    end
  end

  defp bodies(_context) do
    guid = System.unique_integer([:positive]) + 90_000_000
    world = WorldRef.instance(529, guid)

    caster = %Character{
      object: %Object{guid: guid},
      unit: %Unit{
        health: 100,
        max_health: 100,
        race: 1,
        gender: 0,
        level: 60,
        power1: 100,
        max_power1: 100,
        auras: [],
        flags: 0
      },
      player: %Player{flags: 0, skin: 0, face: 0, hair_style: 0, hair_color: 0, facial_hair: 0},
      movement_block: %MovementBlock{position: {1165.0, 1200.0, -56.7, 0.0}},
      internal: %Internal{world: world}
    }

    victim =
      %{
        caster
        | object: %Object{guid: guid + 1},
          unit: %{caster.unit | race: 2, health: 0},
          internal: %{caster.internal | corpse_reclaim: %CorpseReclaim{expires_at: 300_000, released_at: 100}}
      }
      |> Insignia.prepare(true)

    Entity.register(guid)

    for character <- [caster, victim] do
      Metadata.put(character.object.guid, %{
        insignia: Insignia.projection(character),
        alive?: Death.alive?(character),
        ghost?: false
      })

      {x, y, z, _o} = character.movement_block.position
      SpatialHash.update(:players, character.object.guid, world, x, y, z)
    end

    corpse = Corpse.build(victim, [])
    {:ok, _pid} = World.start_entity(corpse)

    on_exit(fn ->
      World.stop_world_entities(world)

      for character <- [caster, victim] do
        Metadata.delete(character.object.guid)
        SpatialHash.remove(:players, character.object.guid)
      end
    end)

    %{caster: caster, victim: victim, corpse: corpse}
  end
end
