defmodule ThistleTea.Game.Entity.Server.Mob.TemporaryThreatTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Spawn
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Guid

  describe "handle_cast/2" do
    test "delivers the aura effect to its mob owner and schedules victim selection" do
      guid = Guid.from_low_guid(:mob, 1, System.unique_integer([:positive, :monotonic]))
      Entity.register(guid)
      on_exit(fn -> Entity.unregister(guid) end)
      character = %Character{object: %Object{guid: 1}, internal: %Internal{}}
      EventSink.emit(character, Effects.temporary_threat(guid, 7, -600))
      assert_receive {:"$gen_cast", {:temporary_threat, 1, 7, -600} = command}

      mob = %Mob{
        object: %Object{guid: guid},
        unit: %Unit{health: 100},
        internal: %Internal{spawn: %Spawn{incarnation_id: 7}, threat: %{1 => 800.0}}
      }

      assert {:noreply, updated} = MobServer.handle_cast(command, mob)
      assert updated.internal.threat[1] == 200.0
      assert is_reference(updated.internal.ai_tick_ref)
      Process.cancel_timer(updated.internal.ai_tick_ref)

      assert {:noreply, restored} = MobServer.handle_cast({:temporary_threat, 1, 7, 0}, updated)
      assert restored.internal.threat[1] == 800.0
      Process.cancel_timer(restored.internal.ai_tick_ref)

      assert {:noreply, ^mob} = MobServer.handle_cast({:temporary_threat, 1, 6, -600}, mob)
      assert {:noreply, ^mob} = MobServer.handle_cast({:temporary_threat, 1, nil, -600}, mob)
    end
  end
end
