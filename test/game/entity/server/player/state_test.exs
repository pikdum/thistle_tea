defmodule ThistleTea.Game.Entity.Server.Player.StateTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Companion, as: CompanionLogic
  alias ThistleTea.Game.Entity.Server.Player.CompanionOwner
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.System.CellActivator
  alias ThistleTea.Game.WorldRef

  describe "struct defaults" do
    test "starts not ready with empty world-presence bookkeeping" do
      state = %State{}

      refute state.ready
      assert state.tracked_entities == MapSet.new()
      assert state.visibility_cells == nil
      assert state.player_guids == []
      assert state.mob_guids == []
      assert state.cell_activator == CellActivator
    end
  end

  describe "leave_world/1" do
    test "resets to a bare player state keeping its boundary references" do
      state = %State{
        connection_pid: self(),
        account: %{username: "test"},
        ready: true,
        target: 42,
        logout_timer: make_ref()
      }

      assert State.leave_world(state) == %State{
               connection_pid: self(),
               account: %{username: "test"}
             }
    end
  end

  describe "worldport bookkeeping" do
    test "emits the previous instance after worldport completion" do
      state =
        State.prepare_worldport(
          %State{},
          WorldRef.instance(389, 12),
          WorldRef.open(1)
        )

      assert state.pending_last_instance_map == 389
      assert %State{pending_last_instance_map: nil} = State.complete_worldport(state)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgUpdateLastInstance{map: 389}}}
    end

    test "does not record an instance on entry" do
      state =
        State.prepare_worldport(
          %State{},
          WorldRef.open(1),
          WorldRef.instance(389, 12)
        )

      assert state.pending_last_instance_map == nil
    end
  end

  describe "suspend_companion/1" do
    test "replaces the active reference with stable restore state" do
      character =
        %Character{unit: %Unit{}, internal: %Internal{}}
        |> CompanionLogic.activate(:guardian, %EntityRef{guid: 123, entry: 1863, spell_id: 712})

      state = CompanionOwner.suspend(%State{character: character})

      assert state.character.unit.summon == 0

      assert state.character.internal.companion ==
               %Companion{kind: :guardian, status: {:suspended, 1863, 712}}
    end
  end
end
