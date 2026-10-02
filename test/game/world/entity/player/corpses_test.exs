defmodule ThistleTea.Game.World.Entity.Player.CorpsesTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Death
  alias ThistleTea.Game.Core.Death.CorpseReclaim
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Corpse
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Corpses
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  setup [:build_ghost]

  describe "repop_at_graveyard/1" do
    test "ignores a stale rescue request after resurrection", %{state: state} do
      {alive, _events} = Death.resurrect(state.character, 1.0, 40_000)
      restored = %{state | character: alive}
      assert Corpses.repop_at_graveyard(restored) == restored
    end
  end

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
    guid = Unique.integer()

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
