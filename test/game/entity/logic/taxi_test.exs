defmodule ThistleTea.Game.Entity.Logic.TaxiTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.Taxi.Node
  alias ThistleTea.Game.Entity.Data.Taxi.Path
  alias ThistleTea.Game.Entity.Data.Taxi.PathNode
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.ExtraAttacks
  alias ThistleTea.Game.Entity.Logic.Falling
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Taxi
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  describe "start/6" do
    test "removes stealth and animal form through the aura lifecycle" do
      shape = %Holder{spell: %Spell{id: 768}, caster_guid: 1, auras: [%AuraData{type: :mod_shapeshift, misc_value: 1}]}
      stealth = %Holder{spell: %Spell{id: 5215}, caster_guid: 1, auras: [%AuraData{type: :mod_stealth}]}
      character = character()
      character = %{character | unit: %{character.unit | auras: [shape, stealth], shapeshift_form: 1}}
      {flying, _effects} = Taxi.start(character, itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      assert flying.unit.auras == []
      assert flying.unit.shapeshift_form == 0
      assert flying.unit.power_type == 0
      assert flying.unit.mount_display_id == 6852
    end

    test "retains warrior stances on a mountless flight and clears flight control on arrival" do
      stance = %Holder{
        spell: %Spell{id: 2457},
        caster_guid: 1,
        auras: [%AuraData{type: :mod_shapeshift, misc_value: 17}]
      }

      character = character()
      character = %{character | unit: %{character.unit | auras: [stance], shapeshift_form: 17}}
      {flying, _effects} = Taxi.start(character, itinerary(), node(4, {64.0, 0.0, 0.0}), 0, make_ref(), 1_000)
      assert flying.unit.auras == [stance]
      assert flying.unit.shapeshift_form == 17
      assert flying.unit.mount_display_id == 0
      assert (flying.unit.flags &&& 0x00100004) == 0x00100004
      landed = Taxi.finish(flying, 3_000)
      assert (landed.unit.flags &&& 0x00100004) == 0
      assert landed.internal.taxi_flight == nil
      assert landed.unit.auras == [stance]
    end

    test "charges the fare and enters a flying mounted spline" do
      token = make_ref()
      destination = node(4, {64.0, 0.0, 0.0})
      itinerary = itinerary()

      pending = ExtraAttacks.grant(character(), 2)
      pending = put_in(pending.internal.fall, %Falling{height: 100.0, far?: true})
      {character, effects} = Taxi.start(pending, itinerary, destination, 6852, token, 1_000)

      refute ExtraAttacks.pending?(character)
      assert character.internal.fall == nil
      assert character.player.coinage == 75
      assert character.unit.mount_display_id == 6852
      assert (character.unit.flags &&& 0x00100004) == 0x00100004
      assert (character.movement_block.movement_flags &&& 0x01000000) != 0
      assert (character.movement_block.spline_flags &&& 0x00000200) != 0
      assert character.movement_block.duration == 2_000
      assert character.internal.movement_start_time == 1_000
      assert character.internal.taxi_flight.token == token
      assert character.internal.taxi_flight.path_ids == [12]
      assert [%Effects.MonsterMove{move_opts: [velocity: 32.0, flying?: true, run?: true]}] = effects
      assert character.internal.broadcast_update?
    end
  end

  describe "receive/4" do
    test "routes taxi spells only to living players with valid paths" do
      character = character()
      effect = %Effect{index: 0, type: :send_taxi, misc_value: 315, implicit_target_a: :target_any}
      spell = Semantics.compile(%Spell{id: 27_998, effects: [effect]})
      context = %CastContext{caster_guid: 2}

      assert {^character, [%Effects.SendTaxiPath{target_guid: 1, path_id: 315, spell_id: 27_998}]} =
               SpellEffect.receive(character, context, spell, 1_000)

      mob = %Mob{object: character.object, unit: character.unit, internal: character.internal}
      dead = put_in(character.unit.health, 0)

      for target <- [mob, dead] do
        {_, effects} = SpellEffect.receive(target, context, spell, 1_000)
        refute Enum.any?(effects, &is_struct(&1, Effects.SendTaxiPath))
      end

      invalid = Semantics.compile(%{spell | effects: [%{effect | misc_value: 0}]})
      assert {^character, []} = SpellEffect.receive(character, context, invalid, 1_000)
    end
  end

  describe "finish/2" do
    test "lands at the last spline point and restores player control" do
      token = make_ref()
      destination = node(4, {80.0, 0.0, 0.0})
      {character, _effects} = Taxi.start(character(), itinerary(), destination, 6852, token, 1_000)
      assert character.internal.taxi_flight.destination_position == {64.0, 0.0, 0.0}
      character = put_in(character.internal.fall, %Falling{height: 100.0, far?: true})

      character = Taxi.finish(character, 1_500)

      assert character.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      assert character.movement_block.spline_nodes == []
      assert character.movement_block.movement_flags == 0
      assert character.unit.mount_display_id == 0
      assert character.internal.fall == nil
      assert (character.unit.flags &&& 0x00100004) == 0
      refute Taxi.active?(character)
      assert character.internal.broadcast_update?
    end
  end

  describe "pause/2" do
    test "checkpoints the current position and trims completed segments" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      paused = Taxi.pause(flying, 2_500)

      assert paused.movement_block.position == {48.0, 0.0, 0.0, 0.0}
      assert paused.movement_block.spline_nodes == []
      assert paused.internal.movement_start_time == nil
      assert paused.internal.taxi_flight.remaining_nodes == [{64.0, 0.0, 0.0}]
      assert paused.internal.taxi_flight.duration_ms == 500
      assert paused.internal.taxi_flight.started_at == nil
      assert paused.internal.taxi_flight.token == nil
      assert paused.unit.mount_display_id == 6852
      assert (paused.unit.flags &&& 0x00100004) == 0x00100004
      assert Movement.sync_position(paused, 100_000) == paused
      assert Taxi.pause(paused, 100_000) == paused
    end

    test "completes a flight whose movement already elapsed" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      landed = Taxi.pause(flying, 3_001)
      refute Taxi.active?(landed)
      assert landed.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      assert landed.unit.mount_display_id == 0
    end
  end

  describe "resume/3" do
    test "finishes a checkpoint within movement tolerance without an empty spline" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      paused = Taxi.pause(flying, 2_999)
      assert paused.internal.taxi_flight.duration_ms == 1
      {landed, []} = Taxi.resume(paused, make_ref(), 100_000)
      assert landed.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      refute Taxi.active?(landed)
      assert landed.unit.mount_display_id == 0
    end

    test "continues the remaining route after offline time without another fare" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      paused = Taxi.pause(flying, 2_500)
      token = make_ref()
      {resumed, effects} = Taxi.resume(paused, token, 100_000)

      assert resumed.movement_block.position == paused.movement_block.position
      assert resumed.movement_block.spline_nodes == [{64.0, 0.0, 0.0}]
      assert resumed.movement_block.duration == 500
      assert resumed.internal.taxi_flight.token == token
      assert resumed.internal.taxi_flight.started_at == 100_000
      assert resumed.internal.taxi_flight.remaining_nodes == nil
      assert resumed.internal.spline_id != flying.internal.spline_id
      assert resumed.player.coinage == 75
      assert [%Effects.MonsterMove{move_opts: [flying?: true, run?: true]}] = effects
      assert Taxi.resume(resumed, make_ref(), 100_100) == {resumed, []}

      paused_again = Taxi.pause(resumed, 100_250)
      assert paused_again.movement_block.position == {56.0, 0.0, 0.0, 0.0}
      assert paused_again.internal.taxi_flight.duration_ms == 250
      {resumed_again, _} = Taxi.resume(paused_again, make_ref(), 200_000)
      landed = Taxi.finish(resumed_again, 200_250)
      assert landed.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      assert landed.player.coinage == 75
      refute Taxi.active?(landed)
    end

    test "cancels a dead passenger's checkpoint without moving to the destination" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      paused = flying |> Taxi.pause(2_500) |> put_in([Access.key(:unit), Access.key(:health)], 0)
      {canceled, []} = Taxi.resume(paused, make_ref(), 100_000)
      refute Taxi.active?(canceled)
      assert canceled.movement_block.position == paused.movement_block.position
      assert canceled.unit.mount_display_id == 0
      assert (canceled.unit.flags &&& 0x00100004) == 0
    end
  end

  describe "cancel/2" do
    test "clears a flight at its current position" do
      {flying, _} = Taxi.start(character(), itinerary(), node(4, {64.0, 0.0, 0.0}), 6852, make_ref(), 1_000)
      canceled = Taxi.cancel(flying, 1_500)
      assert canceled.movement_block.position == {16.0, 0.0, 0.0, 0.0}
      assert canceled.movement_block.spline_nodes == []
      assert canceled.internal.movement_start_time == nil
      assert canceled.unit.mount_display_id == 0
      assert (canceled.unit.flags &&& 0x00100004) == 0
      refute Taxi.active?(canceled)
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{flags: 0, mount_display_id: 0, health: 100, class: 11, race: 4, native_display_id: 49, auras: []},
      player: %Player{coinage: 100},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }
  end

  defp itinerary do
    path = %Path{
      id: 12,
      source_node_id: 2,
      destination_node_id: 4,
      cost: 25,
      nodes: [
        %PathNode{index: 0, map_id: 0, position: {32.0, 0.0, 0.0}},
        %PathNode{index: 1, map_id: 0, position: {64.0, 0.0, 0.0}}
      ]
    }

    %{paths: [path], nodes: path.nodes, total_cost: 25}
  end

  defp node(id, position) do
    %Node{id: id, map_id: 0, position: position, name: "Node", mount_display_ids: %{alliance: 6852}}
  end
end
