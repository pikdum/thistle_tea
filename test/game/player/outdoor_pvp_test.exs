defmodule ThistleTea.Game.Player.OutdoorPvpTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.OutdoorPvp.ResourceRace
  alias ThistleTea.Game.Player.OutdoorPvp
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.System.OutdoorPvp, as: OutdoorSystem
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "reconcile/2" do
    test "replaces ranks and clears rewards at death, exit, and a new login", %{state: state, options: options} do
      state = %{state | outdoor_pvp_tower_buff: 11_413}
      active = OutdoorPvp.reconcile(state, options)
      assert Aura.has_spell?(active.character, 11_413)
      assert OutdoorPvp.reconcile(active, options) == active
      upgraded = OutdoorPvp.reconcile(%{active | outdoor_pvp_tower_buff: 11_414}, options)
      assert Aura.has_spell?(upgraded.character, 11_414)
      refute Aura.has_spell?(upgraded.character, 11_413)

      dead =
        OutdoorPvp.reconcile(
          %{upgraded | character: %{upgraded.character | unit: %{upgraded.character.unit | health: 0}}},
          options
        )

      refute Aura.has_spell?(dead.character, 11_414)

      alive =
        OutdoorPvp.reconcile(
          %{dead | character: %{dead.character | unit: %{dead.character.unit | health: 100}}},
          options
        )

      assert Aura.has_spell?(alive.character, 11_414)
      outside = OutdoorPvp.reconcile(%{alive | outdoor_pvp_tower_buff: nil}, options)
      refute Aura.has_spell?(outside.character, 11_414)
      restored = OutdoorPvp.reconcile(%State{ready: true, character: alive.character}, options)
      refute Aura.has_spell?(restored.character, 11_414)
    end
  end

  describe "update_zone/3" do
    test "applies and removes Silithus favor while walking across zones", %{state: state, options: options} do
      server = start_supervised!({OutdoorSystem, name: nil, race: %ResourceRace{controller: :alliance}})
      options = Keyword.put(options, :server, server)
      state = %{state | character: %{state.character | internal: %{state.character.internal | world: WorldRef.open(1)}}}
      inside = OutdoorPvp.update_zone(state, 1377, options)
      assert Aura.has_spell?(inside.character, 30_754)
      assert is_reference(inside.outdoor_pvp_token)
      assert OutdoorPvp.update_zone(inside, 1377, options) == inside
      outside = OutdoorPvp.update_zone(inside, 14, options)
      refute Aura.has_spell?(outside.character, 30_754)
      assert outside.outdoor_pvp_token == nil
      assert outside.outdoor_pvp_key == {WorldRef.open(1), 14}
      assert OutdoorPvp.update(outside, inside.outdoor_pvp_token, [{2426, 1}], 11_413) == outside
      refute_receive {:"$gen_cast", {:send_packet, %{state: 2426, value: 1}}}
    end
  end

  describe "update/4" do
    test "rejects pending transfers and old owners", %{state: state} do
      token = make_ref()
      current = %{state | outdoor_pvp_token: token}
      assert OutdoorPvp.update(current, make_ref(), [{2426, 1}], 11_413) == current
      pending = %{current | pending_worldport?: true}
      assert OutdoorPvp.update(pending, token, [{2426, 1}], 11_413) == pending
      assert OutdoorPvp.credit(pending, token, 17_696) == pending
      refute_receive {:"$gen_cast", {:send_packet, _}}
    end
  end

  defp character(_context) do
    guid = System.unique_integer([:positive])

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 60, race: 1},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{state: %State{guid: guid, character: character, ready: true}, options: [now: 1000, spell_lookup: &spell/1]}
  end

  defp spell(id),
    do: %Spell{
      id: id,
      school: :holy,
      duration_ms: -1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, implicit_target_a: :caster, base_points: 0}]
    }
end
