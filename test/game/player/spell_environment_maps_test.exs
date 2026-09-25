defmodule ThistleTea.Game.Player.SpellEnvironmentMapsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Player.SpellEnvironment
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  @moduletag :namigator_maps
  @outside {-8949.95, -132.49, 83.53, 0.0}
  @inside {-8914.0, -164.0, 82.0, 0.0}

  setup [:character]

  describe "cast_result/3" do
    test "rejects an indoor cast without spending mana or starting cooldowns", %{state: state, spell: spell} do
      state = move(state, @inside)
      assert {:error, rejected} = Spellcasting.cast_result(state, spell, <<0::16>>)
      assert rejected.character.internal.casting == nil
      assert rejected.character.internal.cooldowns == %{}
      assert rejected.character.unit.power1 == 100
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x55}}}
    end
  end

  describe "complete/1" do
    test "rechecks current terrain when a cast started outside completes indoors", %{state: state, spell: spell} do
      assert {:ok, casting} = Spellcasting.cast_result(state, spell, <<0::16>>)
      assert casting.character.internal.casting
      rejected = casting |> move(@inside) |> Spellcasting.complete()
      assert rejected.character.internal.casting == nil
      assert rejected.character.unit.power1 == 100
      refute Aura.has_spell?(rejected.character, spell.id)
      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{reason: 0x55}}}
    end

    test "allows the same cast to complete outside", %{state: state, spell: spell} do
      assert {:ok, casting} = Spellcasting.cast_result(state, spell, <<0::16>>)
      completed = Spellcasting.complete(casting)
      assert completed.character.internal.casting == nil
      assert completed.character.unit.power1 == 90
      assert Aura.has_spell?(completed.character, spell.id)
    end
  end

  describe "reconcile/2" do
    test "removes an outdoor aura on movement and after a new owner restores indoors", %{state: state, spell: spell} do
      {character, _events} = Aura.apply_spell(state.character, state.guid, 50, spell, 1000)
      outside = SpellEnvironment.reconcile(%{state | character: character})
      assert outside.character.internal.outdoors? == true
      assert Aura.has_spell?(outside.character, spell.id)
      assert SpellEnvironment.reconcile(outside) == outside

      inside = outside |> move(@inside) |> SpellEnvironment.reconcile()
      assert inside.character.internal.outdoors? == false
      refute Aura.has_spell?(inside.character, spell.id)

      restored = SpellEnvironment.restore(move(%{state | character: character}, @inside).character)
      refute Aura.has_spell?(restored, spell.id)
    end
  end

  defp character(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    {:ok, _owner} = Entity.register(guid)
    on_exit(fn -> Entity.unregister(guid) end)

    spell = %Spell{
      id: 95_000_000 + guid,
      name: "Outdoor test cast",
      school: :nature,
      cast_time_ms: 1500,
      duration_ms: -1,
      power_type: 0,
      mana_cost: 10,
      attributes: MapSet.new([:only_outdoors]),
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mod_increase_speed, base_points: 40, implicit_target_a: :caster}
      ]
    }

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{level: 50, health: 100, max_health: 100, power1: 100, max_power1: 100, power_type: 0, auras: []},
      player: %Player{},
      movement_block: struct!(%MovementBlock{position: @outside}, MovementBlock.player_speeds()),
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }

    %{state: %State{guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character}, spell: spell}
  end

  defp move(%State{character: character} = state, position) do
    %{state | character: %{character | movement_block: %{character.movement_block | position: position}}}
  end
end
