defmodule ThistleTea.Game.Player.GameObjectsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.GameObjectTemplate
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Player.GameObjects
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.WorldRef

  describe "use_object/2" do
    test "sits the player in the seat returned by a chair game object" do
      entry = System.unique_integer([:positive])
      guid = Guid.from_low_guid(:game_object, entry, System.unique_integer([:positive]))
      template = %GameObjectTemplate{entry: entry, type: 7, size: 1.0, data: [1, 1]}
      :ets.insert(GameObjectTemplateLoader, {entry, template})

      owner = start_chair_owner(guid, {:ok, {1.0, 2.0, 3.0, 1.5}, 5})

      on_exit(fn ->
        :ets.delete(GameObjectTemplateLoader, entry)
        if Process.alive?(owner), do: Process.exit(owner, :kill)
      end)

      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 10, stand_state: 0},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {1.0, 1.0, 3.0, 0.0}}
      }

      state = GameObjects.use_object(%{guid: 1, character: character}, guid)

      assert state.character.unit.stand_state == 5
      assert_receive {:"$gen_cast", {:start_teleport, 1.0, 2.0, 3.0, 1.5, %WorldRef{map_id: 0}}}
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgStandstateUpdate{stand_state: 5}}}
    end
  end

  defp start_chair_owner(guid, result) do
    parent = self()

    spawn(fn ->
      {:ok, _owner} = Entity.register(guid)
      send(parent, :chair_owner_ready)
      serve_chair(result)
    end)
    |> tap(fn _pid -> assert_receive :chair_owner_ready end)
  end

  defp serve_chair(result) do
    receive do
      {:"$gen_call", from, {:chair_seat, %WorldRef{map_id: 0}, {1.0, 1.0, 3.0}}} -> GenServer.reply(from, result)
    end
  end
end
