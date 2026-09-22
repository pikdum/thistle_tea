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
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Logic.Taxi
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Semantics

  describe "start/7" do
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
      {character, effects} = Taxi.start(pending, itinerary, destination, 6852, token, 1_000)

      refute ExtraAttacks.pending?(character)
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
    test "lands at the taxi node and restores player control" do
      token = make_ref()
      destination = node(4, {64.0, 0.0, 0.0})
      {character, _effects} = Taxi.start(character(), itinerary(), destination, 6852, token, 1_000)

      character = Taxi.finish(character, 1_500)

      assert character.movement_block.position == {64.0, 0.0, 0.0, 0.0}
      assert character.movement_block.spline_nodes == []
      assert character.movement_block.movement_flags == 0
      assert character.unit.mount_display_id == 0
      assert (character.unit.flags &&& 0x00100004) == 0
      refute Taxi.active?(character)
      assert character.internal.broadcast_update?
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
