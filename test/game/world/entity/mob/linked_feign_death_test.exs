defmodule ThistleTea.Game.World.Entity.Mob.LinkedFeignDeathTest do
  use ExUnit.Case, async: false

  alias ThistleTea.DB.Mangos
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Creature.LinkedFeignDeath
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Loader.Faction, as: FactionLoader
  alias ThistleTea.Game.World.Loader.Mob, as: MobLoader
  alias ThistleTea.Game.World.Loader.Mob.Builder, as: MobBuilder
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.FactionFixtures
  alias ThistleTea.Test.Unique

  setup [{FactionFixtures, :seed}, :pack]

  describe "linked feigned-death lifecycle" do
    test "projects the fallen pose, revives and resumes combat", %{mobs: [first, second], player: player} do
      Entity.debug_damage(second, player, 1)
      Entity.debug_damage(first, player, 1_000)

      fallen =
        await(
          first,
          &(LinkedFeignDeath.active?(&1) and Enum.any?(&1.unit.auras, fn holder -> holder.spell.id == 19_951 end))
        )

      assert fallen.unit.health == 1
      assert fallen.internal.loot.session == nil
      refute fallen.internal.death_finalized?
      assert Metadata.query(first, [:health]) == %{health: 1}
      assert Enum.any?(fallen.unit.auras, &(&1.spell.id == 19_951))
      Entity.request_update_from(first, self())
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{unit: %{health: 1, stand_state: 7}}}}, 1_000

      revived = await(first, &(&1.unit.health == 100 and not LinkedFeignDeath.active?(&1)))
      assert revived.unit.stand_state == 0
      assert revived.unit.target == player
      assert revived.internal.in_combat
      assert revived.internal.threat[player] > 0
      refute Enum.any?(revived.unit.auras, &(&1.spell.id == 19_951))
      assert Process.alive?(Entity.pid(first))
    end

    test "removes the whole defeated pack and can respawn it cleanly", %{mobs: mobs, player: player} do
      for guid <- mobs, do: Entity.debug_damage(guid, player, 1_000)
      for guid <- mobs, do: await(guid, &LinkedFeignDeath.active?/1)

      for guid <- mobs do
        dead = await(guid, & &1.internal.loot.corpse_removed?)
        assert dead.unit.health == 0
        refute dead.internal.in_combat
        refute LinkedFeignDeath.active?(dead)
        assert World.position(guid) == nil
        assert Metadata.query(guid, [:health]) == %{health: 0}
        send(Entity.pid(guid), {:script_respawn, true})
        respawned = await(guid, &(&1.unit.health == 100 and not &1.internal.loot.corpse_removed?))
        assert respawned.unit.stand_state in [nil, 0]
        assert respawned.internal.linked_feign_death.revive_at == nil
        refute respawned.internal.death_finalized?
      end
    end

    test "a fighting hound in another copy cannot revive an isolated hound", %{world: world} do
      other_world = WorldRef.instance(world.map_id, Unique.integer())
      other_player = player(other_world)
      outsider = start_hound(other_world)
      isolated_world = WorldRef.instance(world.map_id, Unique.integer())
      isolated_player = player(isolated_world)
      isolated = start_hound(isolated_world)

      Entity.debug_damage(outsider, other_player, 1)
      await(outsider, & &1.internal.in_combat)
      Entity.debug_damage(isolated, isolated_player, 1_000)
      await(isolated, &LinkedFeignDeath.active?/1)
      assert await(isolated, & &1.internal.loot.corpse_removed?).unit.health == 0
      assert await(outsider, & &1.internal.in_combat).unit.health > 1
    end

    test "a wipe clears the fallen timer and leaves the hound ready for another pull", %{
      mobs: [first, _],
      player: player
    } do
      Entity.debug_damage(first, player, 1_000)
      await(first, &LinkedFeignDeath.active?/1)
      Metadata.update(player, %{alive?: false})
      restored = await(first, &(not &1.internal.in_combat and &1.unit.health == 100))
      refute LinkedFeignDeath.active?(restored)
      assert restored.unit.stand_state in [nil, 0]
      assert restored.internal.threat == %{}
    end
  end

  defp pack(_context) do
    world = WorldRef.instance(409, Unique.integer())
    %{world: world, player: player(world), mobs: [start_hound(world), start_hound(world)]}
  end

  defp player(world) do
    guid = Unique.integer()
    {:ok, _} = Entity.register(guid)
    metadata = %{alive?: true, level: 60, unit_flags: 0, bounding_radius: 0.5, combat_reach: 1.5}
    Metadata.put(guid, Map.merge(metadata, FactionLoader.metadata(1)))
    SpatialHash.insert(:players, guid, world, 0.0, 0.0, 0.0)

    on_exit(fn ->
      SpatialHash.remove(:players, guid)
      Metadata.delete(guid)
    end)

    guid
  end

  defp start_hound(world) do
    events =
      Enum.map(CreatureScript.events(11_671), fn event ->
        %{event | actions: Enum.map(event.actions, &Enum.map(&1, fn step -> resolve(step) end))}
      end)

    spellbook = Map.new([19_951, 17_683, 19_823, 19_771], &{&1, spell(&1)})

    mob =
      %Mangos.Creature{
        guid: Unique.integer(),
        id: 11_671,
        map: world.map_id,
        position_x: 0.0,
        position_y: 0.0,
        position_z: 0.0,
        orientation: 0.0,
        spawntimesecsmin: 3_600,
        spawntimesecsmax: 3_600,
        modelid: 1,
        selected_level: 60,
        curhealth: 100,
        creature_movement: [],
        creature_addon: nil,
        game_event_creature: nil,
        ai_events: events,
        spellbook: spellbook,
        creature_template: %Mangos.CreatureTemplate{
          entry: 11_671,
          name: "Core Hound #{Unique.integer()}",
          health_multiplier: 1.0,
          unit_class: 1,
          faction_alliance: 14,
          extra_flags: 2,
          melee_base_attack_time: 2_000
        }
      }
      |> MobBuilder.build()
      |> then(&%{&1 | internal: %{&1.internal | world: world}})

    on_exit(fn -> World.stop_entity(mob.object.guid) end)
    {:ok, _} = MobLoader.start_mob(mob)
    await(mob.object.guid, &is_struct(&1.internal.linked_feign_death))
    mob.object.guid
  end

  defp resolve(%ScriptStep{command: :talk} = step),
    do: %{step | texts: [%{text: "Core Hound changes state.", chat_type: :text_emote, emote_id: 0}]}

  defp resolve(%ScriptStep{command: :linked_feign_death} = step),
    do: %{
      step
      | datalong: 400,
        sub_scripts: Map.new(step.sub_scripts, fn {id, steps} -> {id, Enum.map(steps, &resolve/1)} end)
    }

  defp resolve(step), do: step

  defp spell(19_951),
    do: %Spell{
      id: 19_951,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_pacify, implicit_target_a: :caster}]
    }

  defp spell(17_683),
    do: %Spell{id: 17_683, effects: [%Effect{index: 0, type: :heal, base_points: 999, implicit_target_a: :caster}]}

  defp spell(id), do: %Spell{id: id, effects: []}

  defp await(guid, predicate, attempts \\ 200)

  defp await(guid, predicate, attempts) when attempts > 0 do
    state = :sys.get_state(Entity.pid(guid))

    if predicate.(state) do
      state
    else
      Process.sleep(10)
      await(guid, predicate, attempts - 1)
    end
  end

  defp await(guid, _predicate, 0), do: flunk("Hound #{guid} did not complete its transition")
end
