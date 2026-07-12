defmodule ThistleTea.Game.Network.SessionTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Connection
  alias ThistleTea.Game.Network.Session
  alias ThistleTea.Game.World.System.CellActivator

  describe "struct defaults" do
    test "starts not ready with empty world-presence bookkeeping" do
      session = %Session{}

      refute session.ready
      assert session.tracked_entities == MapSet.new()
      assert session.visibility_cells == nil
      assert session.player_guids == []
      assert session.mob_guids == []
      assert session.cell_activator == CellActivator
    end
  end

  describe "leave_world/1" do
    test "resets to a bare session keeping the connection and account" do
      conn = %Connection{}

      session = %Session{
        conn: conn,
        account: %{username: "test"},
        ready: true,
        target: 42,
        latency: 30,
        logout_timer: make_ref()
      }

      assert Session.leave_world(session) == %Session{conn: conn, account: %{username: "test"}}
    end
  end

  describe "suspend_active_pet/1" do
    test "clears the live guid while retaining the pet restore state" do
      character = %Character{
        unit: %Unit{summon: 123},
        internal: %Internal{active_pet_entry: 1863, active_pet_spell_id: 712}
      }

      state = Session.suspend_active_pet(%Session{character: character})

      assert state.character.unit.summon == 0
      assert state.character.internal.active_pet_entry == 1863
      assert state.character.internal.active_pet_spell_id == 712
    end
  end
end
