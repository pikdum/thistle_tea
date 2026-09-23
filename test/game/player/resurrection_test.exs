defmodule ThistleTea.Game.Player.ResurrectionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.AreaTriggerTeleport
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Corpse
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Resurrection, as: ResurrectionLogic
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.MovementControl
  alias ThistleTea.Game.Player.Resurrection
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.Travel
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.AreaTrigger
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.ResurrectionTarget
  alias ThistleTea.Game.World.System.Instance
  alias ThistleTea.Game.WorldRef

  @map 900_041
  @dungeon 900_042

  setup [:spirit_run]

  describe "validate_repeat/3" do
    test "casts at a released body while its owner is on another map", %{
      caster: caster,
      state: state,
      spell: spell,
      corpse: corpse
    } do
      for target <- [Target.corpse(corpse.object.guid, state.guid), Target.unit(state.guid)] do
        info = ResurrectionTarget.info(caster, target)
        assert info.position == {WorldRef.open(@map), 1.0, 0.0, 0.0}
        assert :ok = Spellcasting.validate_repeat(%State{guid: caster.object.guid, character: caster}, spell, target)
        assert SpellTargetResolver.resolve(caster, spell, target) == [state.guid]
      end
    end

    test "rejects missing, mismatched, living, and distant bodies", %{
      caster: caster,
      state: state,
      spell: spell,
      corpse: corpse
    } do
      target = Target.corpse(corpse.object.guid, state.guid)
      wrong = Target.corpse(corpse.object.guid + 1, state.guid)
      assert SpellTargetResolver.resolve(caster, spell, wrong) == []
      distant = put_in(caster.movement_block.position, {100.0, 0.0, 0.0, 0.0})
      assert SpellTargetResolver.resolve(distant, spell, target) == []
      other_copy = put_in(caster.internal.world, WorldRef.instance(@map, 1))
      assert SpellTargetResolver.resolve(other_copy, spell, target) == []
      Metadata.update(state.guid, %{alive?: true, ghost?: false})
      assert SpellTargetResolver.resolve(caster, spell, target) == []
      Metadata.update(state.guid, %{alive?: false, ghost?: true})
      World.stop_entity(corpse.object.guid)
      assert SpellTargetResolver.resolve(caster, spell, target) == []
    end
  end

  describe "complete/2" do
    test "launches across the ghost's world and aborts removed bodies before costs", %{
      caster: caster,
      state: state,
      spell: spell,
      corpse: corpse
    } do
      target = Target.corpse(corpse.object.guid, state.guid)
      spell = %{spell | cast_time_ms: 1000, mana_cost: 10, power_type: 0}
      casting = Casting.start(caster, spell, target, 100)
      completed = Casting.complete(casting, 1100)
      assert completed.unit.power1 == 70

      assert Enum.any?(
               completed.internal.events,
               &match?(%Effects.DeliverSpell{target_guid: guid} when guid == state.guid, &1)
             )

      World.stop_entity(corpse.object.guid)
      aborted = Casting.complete(casting, 1100)
      assert aborted.unit.power1 == 80
      refute Enum.any?(aborted.internal.events, &is_struct(&1, Effects.DeliverSpell))
      assert Enum.any?(aborted.internal.events, &match?(%Effects.SpellCastFailed{reason: :bad_targets}, &1))
    end
  end

  describe "respond/3" do
    test "matching arrival revives once and removes all corpse projections", %{
      state: state,
      corpse: corpse,
      offer: offer
    } do
      accepted = Resurrection.respond(%{state | pending_repop: %{token: make_ref()}}, offer.caster_guid, 1)
      assert accepted.pending_repop == nil
      assert_receive {:"$gen_cast", {:accept_resurrection, accepted_offer}}
      assert Resurrection.respond(accepted, offer.caster_guid, 1) == accepted
      refute_receive {:"$gen_cast", {:accept_resurrection, _}}
      same_world = put_in(accepted.character.internal.world, WorldRef.open(@map))
      {:noreply, moving} = PlayerServer.handle_cast({:accept_resurrection, accepted_offer}, same_world)
      refute Death.alive?(moving.character)
      assert Entity.pid(corpse.object.guid)
      assert_receive {:"$gen_cast", {:send_packet, %Message.MsgMoveTeleportAck{} = packet}}
      {packet, moving} = MovementControl.prepare(packet, moving)
      assert Travel.teleport_ack(moving, state.guid, packet.counter + 1) == moving
      restored = Travel.teleport_ack(moving, state.guid, packet.counter)
      assert Death.alive?(restored.character)
      assert restored.character.unit.health == 70
      assert restored.character.unit.power1 == 80
      assert restored.character.internal.pending_resurrect == nil
      assert Entity.pid(corpse.object.guid) == nil
      assert World.position(corpse.object.guid) == nil
      assert Metadata.query(corpse.object.guid, [:owner]) == nil
      assert Travel.teleport_ack(restored, state.guid, packet.counter) == restored
    end

    test "cross-map recovery waits for its worldport and competing travel cancels it", %{state: state, offer: offer} do
      accepted = Resurrection.respond(state, offer.caster_guid, 1)
      assert_receive {:"$gen_cast", {:accept_resurrection, accepted_offer}}
      {:noreply, moving} = PlayerServer.handle_cast({:accept_resurrection, accepted_offer}, accepted)
      assert moving.pending_worldport?
      refute Death.alive?(moving.character)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgNewWorld{} = packet}}
      {_, moving} = MovementControl.prepare(packet, moving)
      assert Resurrection.arrive(moving, {:teleport, 0}) == moving
      canceled = Resurrection.cancel_transfer(moving)
      assert Resurrection.arrive(canceled, :worldport) == canceled
      assert Death.alive?(Resurrection.arrive(moving, :worldport).character)
    end

    test "logout clears an offer before retaining the character", %{state: state} do
      character = %{state.character | id: state.guid}
      state = %{state | character: character}
      State.leave_world(state)
      assert CharacterStore.get(state.guid).internal.pending_resurrect == nil
      :ets.delete(CharacterStore, state.guid)
    end
  end

  describe "start/2" do
    test "denied admission revives in place and clears the corpse", %{state: state, offer: offer, corpse: corpse} do
      :ets.insert(AreaTrigger, {{:instance_map, @dungeon}, true})
      :ets.insert(MapTemplate, {@dungeon, 2, nil})
      offer = %{offer | phase: :accepted, position: {WorldRef.instance(@dungeon, 999_999), 100.0, 200.0, 300.0}}
      state = %{state | character: ResurrectionLogic.put(state.character, offer)}

      assert {:finished, restored} = Resurrection.start(state, offer)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgRaidGroupOnly{}}}
      assert Death.alive?(restored.character)
      assert restored.character.internal.world == state.character.internal.world
      assert restored.character.movement_block.position == state.character.movement_block.position
      assert restored.character.internal.pending_resurrect == nil
      assert Entity.pid(corpse.object.guid) == nil
    end

    test "a changed copy uses its entrance instead of the old interior", %{state: state, offer: offer} do
      :ets.insert(AreaTrigger, [
        {{:instance_map, @dungeon}, true},
        {{:entrance, @dungeon}, %AreaTriggerTeleport{target_map: @dungeon, x: 5.0, y: 6.0, z: 7.0, orientation: 0.5}}
      ])

      offer = %{offer | phase: :accepted, position: {WorldRef.instance(@dungeon, 999_999), 100.0, 200.0, 300.0}}
      state = %{state | character: ResurrectionLogic.put(state.character, offer)}

      assert {:teleport, {%WorldRef{map_id: @dungeon} = world, 5.0, 6.0, 7.0, 0.5}, _} =
               Resurrection.start(state, offer)

      assert world.instance_id != 999_999
      Instance.leave(state.guid, world)
      Instance.reset(state.guid)
    end
  end

  defp spirit_run(_context) do
    guid = System.unique_integer([:positive]) + 40_000_000
    world = WorldRef.open(@map)
    :ets.insert(AreaTrigger, {{:instance_map, @map}, false})

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{
        health: 1,
        max_health: 100,
        power1: 0,
        max_power1: 80,
        power4: 0,
        max_power4: 100,
        race: 1,
        gender: 0,
        level: 30,
        auras: []
      },
      player: %Player{flags: 0x10, skin: 0, face: 0, hair_style: 0, hair_color: 0, facial_hair: 0},
      movement_block: %MovementBlock{position: {1.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world}
    }

    corpse = Corpse.build(character, [])
    {:ok, _} = World.start_entity(corpse)
    Metadata.put(guid, %{alive?: false, ghost?: true, unit_flags: 0, creature_type: 7})

    caster = %{
      character
      | object: %Object{guid: guid + 1},
        unit: %{character.unit | health: 100, power1: 80},
        player: %{character.player | flags: 0}
    }

    context = %CastContext{
      caster_guid: caster.object.guid,
      caster_position: {world, 2.0, 0.0, 0.0},
      caster_orientation: 1.5
    }

    spell = %Spell{
      id: 2006,
      name: "Resurrection",
      range_yards: 30.0,
      effects: [%Effect{type: :resurrect_new, implicit_target_a: :target_ally, base_points: 70, misc_value: 135}]
    }

    {character, _} = ResurrectionLogic.offer(character, context, spell, 70, 135)
    character = %{character | internal: %{character.internal | world: WorldRef.open(@map + 10)}}

    on_exit(fn ->
      World.stop_entity(corpse.object.guid)
      World.remove_position(character)
      Metadata.delete(guid)
      :ets.delete(AreaTrigger, {:instance_map, @map})
      :ets.delete(AreaTrigger, {:instance_map, @dungeon})
      :ets.delete(AreaTrigger, {:entrance, @dungeon})
      :ets.delete(MapTemplate, @dungeon)
      Instance.reset(guid)
    end)

    %{
      state: %State{guid: guid, ready: true, character: character},
      caster: caster,
      spell: spell,
      corpse: corpse,
      offer: character.internal.pending_resurrect
    }
  end
end
