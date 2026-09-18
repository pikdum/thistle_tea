defmodule ThistleTea.Game.Entity.Logic.TotemsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Commands
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Totems
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.EntitySupervisor

  setup [:totem]

  describe "dismiss_all/1" do
    test "clears slots and queues each child exactly once", %{guid: guid} do
      character = character(%{1 => guid, 2 => guid})
      dismissed = Totems.dismiss_all(character)
      assert dismissed.internal.totem_guids == %{}
      assert [%Effects.DespawnEntity{target_guid: ^guid}] = dismissed.internal.events
      assert Totems.dismiss_all(dismissed) == dismissed
    end
  end

  describe "handle_info/2" do
    test "a late totem start is stopped immediately for a dead player", %{guid: guid, pid: pid} do
      character = character(%{})
      character = %{character | unit: %{character.unit | health: 0}}
      command = %Commands.TotemStarted{slot: 2, guid: guid}
      {:noreply, state} = PlayerServer.handle_info(command, %State{character: character})
      assert state.character.internal.totem_guids == %{}
      assert state.character.internal.events == []
      refute Process.alive?(pid)
      refute Entity.online?(guid)
    end
  end

  describe "leave_world/1" do
    test "stops totems and saves cleared slots on logout", %{guid: guid, pid: pid} do
      character = character(%{2 => guid}) |> CharacterStore.put()
      assert %State{character: nil} = State.leave_world(%State{character: character})
      assert CharacterStore.get(character.id).internal.totem_guids == %{}
      assert CharacterStore.get(character.id).internal.events == []
      refute Process.alive?(pid)
    end
  end

  defp totem(_) do
    guid = System.unique_integer([:positive]) + 9_000_000
    {:ok, pid} = EntitySupervisor.start_child(guid, {Agent, fn -> Entity.register(guid) end})
    on_exit(fn -> if Process.alive?(pid), do: World.stop_entity(pid) end)
    %{guid: guid, pid: pid}
  end

  defp character(totems) do
    id = System.unique_integer([:positive]) + 10_000_000
    on_exit(fn -> :ets.delete(CharacterStore, id) end)

    %Character{
      id: id,
      object: %Object{guid: id},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{totem_guids: totems}
    }
  end
end
