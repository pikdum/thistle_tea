defmodule ThistleTea.Game.Player.MoverTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.MovementHandoff
  alias ThistleTea.Game.Entity.Logic.SafePosition
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.Dispatch
  alias ThistleTea.Game.Network.Packet
  alias ThistleTea.Game.Player.Input
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Player.Mover
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Presence
  alias ThistleTea.Game.WorldRef

  setup [:player]

  describe "select/2" do
    test "acknowledgements cannot select a unit outside current control", %{state: state, other: other} do
      assert Mover.select(state, other) == state
      controlled = control(state, other)
      assert Mover.select(controlled, state.guid) == controlled
      selected = Mover.select(controlled, other)
      assert selected.client_mover_guid == other
      assert Mover.select(selected, 0).client_mover_guid == nil
      assert Mover.select(selected, 0).active_mover_guid == other

      possessed =
        put_in(
          state.character.internal.possession,
          %Possession{caster_guid: other, spell_id: 605, original_faction_template: 1}
        )

      assert Input.handle(%Message.CmsgSetActiveMover{guid: state.guid}, possessed) == possessed
    end
  end

  describe "release/3" do
    test "applies a final body snapshot without cancelling possession's channel", %{state: state, other: other} do
      state = control(state, other)
      cast = %Cast{spell: %Spell{id: 605}, phase: :channel_tick, ends_at: Time.now() + 60_000}
      state = put_in(state.character.internal.casting, cast)
      state = %{state | character: MovementHandoff.offer(state.character, state.guid, Time.now())}
      payload = payload(state, 1.0)
      released = Mover.release(state, state.guid, payload)
      assert released.client_mover_guid == nil
      assert released.active_mover_guid == other
      assert released.character.internal.casting == cast
      assert released.character.movement_block.position == {1.0, 0.0, 0.0, 0.0}
      assert World.position(state.guid) == {state.character.internal.world, 1.0, 0.0, 0.0}
      assert Mover.release(released, state.guid, payload(state, 2.0)) == released
      cancel_tick(released)
    end

    test "routes a released remote mover once and never relocates the caster", %{state: state, other: other} do
      Entity.register(other)
      state = %{state | client_mover_guid: other}
      payload = payload(state, 1.0)
      released = Mover.release(state, other, payload)
      assert released.character == state.character
      assert_receive {:"$gen_cast", {:finish_movement, _, ^payload}}
      assert Mover.release(released, other, payload) == released
      refute_received {:"$gen_cast", {:finish_movement, _, _}}
    end

    test "rejects a stale guid and a remote mover that remains controlled", %{state: state, other: other} do
      assert Mover.release(state, other, <<>>) == state
      state = %{control(state, other) | client_mover_guid: other}
      assert Mover.release(state, other, <<>>) == state
    end

    test "the recipient accepts a final snapshot only before new movement", %{state: state, other: other} do
      state = %{state | character: MovementHandoff.offer(state.character, other, Time.now())}

      assert {:noreply, moved, {:continue, :maybe_broadcast_update}} =
               PlayerServer.handle_cast({:finish_movement, other, payload(state, 1.0)}, state)

      assert moved.character.movement_block.position == {1.0, 0.0, 0.0, 0.0}
      assert Movement.finish_input(moved, other, payload(state, 2.0)) == moved

      current = Movement.handle(%Message.MsgMove{payload: payload(state, 0.0), opcode: 0xEE}, state)
      assert current.character.internal.movement_handoff == nil
      assert Movement.finish_input(current, other, payload(state, 2.0)) == current
      cancel_tick(moved)
      cancel_tick(current)
    end
  end

  describe "from_binary/1" do
    test "dispatches the previous mover and movement snapshot", %{state: state} do
      payload = payload(state, 1.0)
      packet = %Packet{opcode: 0x2D1, payload: <<state.guid::little-size(64), payload::binary>>}
      assert %Message.CmsgMoveNotActiveMover{guid: guid, movement_payload: ^payload} = Dispatch.to_message(packet)
      assert guid == state.guid
    end
  end

  defp control(state, other) do
    character = Companion.activate(state.character, :possession, %EntityRef{guid: other, entry: 0, spell_id: 605})
    %{state | character: character, active_mover_guid: other}
  end

  defp payload(state, x) do
    %{state.character.movement_block | position: {x, 0.0, 0.0, 0.0}} |> MovementBlock.movement_info_to_binary()
  end

  defp cancel_tick(%State{player_tick_ref: ref}) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_tick(_state), do: :ok

  defp player(_context) do
    guid = System.unique_integer([:positive, :monotonic])
    other = System.unique_integer([:positive, :monotonic])
    world = WorldRef.instance(451, guid)
    position = {0.0, 0.0, 0.0, 0.0}
    Entity.register(guid)

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: position, movement_flags: 0},
      internal: %Internal{world: world, safe_position: %SafePosition{world: world, position: position}}
    }

    Presence.enter(character, %{})
    on_exit(fn -> Presence.leave(character) end)

    %{
      state: %State{guid: guid, ready: true, character: character, active_mover_guid: guid, client_mover_guid: guid},
      other: other
    }
  end
end
