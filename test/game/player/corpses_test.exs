defmodule ThistleTea.Game.Player.CorpsesTest do
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
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.Corpses
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:build_ghost]

  describe "send_reclaim_delay/2" do
    test "projects remaining time on reconnect without restarting it", %{state: state} do
      Corpses.send_reclaim_delay(state.character, 35_000)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCorpseReclaimDelay{delay_ms: 35_000}}}
      Corpses.send_reclaim_delay(state.character, 70_000)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgCorpseReclaimDelay{}}}

      {alive, _events} = Death.resurrect(state.character, 1.0, 40_000)
      Corpses.send_reclaim_delay(alive, 40_000)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgCorpseReclaimDelay{}}}
    end
  end

  describe "reclaim/2" do
    test "rejects early attempts, then restores half resources and removes the corpse", %{state: state, corpse: corpse} do
      assert Corpses.reclaim(state, 69_999) == state
      assert Entity.pid(corpse.object.guid)
      restored = Corpses.reclaim(state, 70_000)
      refute Death.ghost?(restored.character)
      assert restored.character.unit.health == 50
      assert restored.character.unit.power1 == 40
      assert restored.character.internal.corpse_reclaim == %CorpseReclaim{expires_at: 600_000}
      assert Entity.pid(corpse.object.guid) == nil
      assert World.position(corpse.object.guid) == nil
      assert Metadata.query(corpse.object.guid, [:owner]) == nil
      assert Corpses.reclaim(restored, 80_000) == restored
    end

    test "rejects a distant, missing, or different-copy corpse", %{state: state, corpse: corpse} do
      far = put_in(state.character.movement_block.position, {40.0, 0.0, 0.0, 0.0})
      assert Corpses.reclaim(far, 70_000) == far
      other_copy = put_in(state.character.internal.world, WorldRef.instance(0, 2))
      assert Corpses.reclaim(other_copy, 70_000) == other_copy
      World.stop_entity(corpse.object.guid)
      assert Corpses.reclaim(state, 70_000) == state
    end

    test "requires a released ghost and a ready session", %{state: state} do
      unreleased = put_in(state.character.player.flags, 0)
      assert Corpses.reclaim(unreleased, 70_000) == unreleased
      unready = %{state | ready: false}
      assert Corpses.reclaim(unready, 70_000) == unready
      assert Corpses.release(state) == state
      assert Corpses.release(unready) == unready
    end
  end

  defp build_ghost(_context) do
    guid = System.unique_integer([:positive]) + 20_000_000

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 1, max_health: 100, max_power1: 80, race: 1, gender: 0, level: 10, auras: []},
      player: %Player{flags: 0x10, skin: 0, face: 0, hair_style: 0, hair_color: 0, facial_hair: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{corpse_reclaim: %CorpseReclaim{expires_at: 600_000, released_at: 10_000}}
    }

    corpse = Corpse.build(character, [])
    {:ok, _pid} = World.start_entity(corpse)
    on_exit(fn -> World.stop_entity(corpse.object.guid) end)
    %{state: %State{guid: guid, ready: true, character: character}, corpse: corpse}
  end
end
