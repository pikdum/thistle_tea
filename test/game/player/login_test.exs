defmodule ThistleTea.Game.Player.LoginTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Login

  defmodule TransportUpdateServer do
    @moduledoc false
    use GenServer

    alias ThistleTea.Game.Entity.Registry, as: EntityRegistry

    def start_link({guid, update}) do
      GenServer.start_link(__MODULE__, update, name: EntityRegistry.via(guid))
    end

    @impl GenServer
    def init(update), do: {:ok, update}

    @impl GenServer
    def handle_call(:transport_update, _from, update), do: {:reply, {:ok, update}, update}
  end

  describe "restore_companion/1" do
    test "does not resummon the saved pet while the character is dead" do
      state = %{character: character(health: 0)}

      assert Login.restore_companion(state) == state
    end

    test "does not resummon the saved pet while the character is a ghost" do
      ghost = character(health: 1, player_flags: 0x10)
      refute Death.alive?(ghost)

      state = %{character: ghost}

      assert Login.restore_companion(state) == state
    end
  end

  describe "worldport_updates/1" do
    test "orders the attached transport before the player" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
      transport_guid = Guid.from_low_guid(:mo_transport, System.unique_integer([:positive]))

      transport_update = %UpdateObject{
        update_type: :create_object2,
        object_type: :game_object,
        object: %Object{guid: transport_guid},
        movement_block: %MovementBlock{position: {100.0, 200.0, 30.0, 0.75}}
      }

      start_supervised!({TransportUpdateServer, {transport_guid, transport_update}})

      character = %Character{
        object: %Object{guid: player_guid},
        movement_block: %MovementBlock{
          position: {1.0, 2.0, 3.0, 0.5},
          transport_guid: transport_guid,
          transport_position: {4.0, 5.0, 6.0, 0.75}
        }
      }

      assert {
               aligned,
               [
                 %UpdateObject{object: %Object{guid: ^transport_guid}},
                 %UpdateObject{object: %Object{guid: ^player_guid}, movement_block: player_movement}
               ]
             } = Login.worldport_updates(character)

      assert %{aligned.movement_block | update_flag: 0x71} == player_movement
      assert player_movement.transport_guid == transport_guid
      assert player_movement.update_flag == 0x71
      assert player_movement.timestamp == 0
      assert player_movement.position == {99.5185616753786, 206.38499938446245, 36.0, 1.5}
    end

    test "includes only the player when detached" do
      player_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

      character = %Character{
        object: %Object{guid: player_guid},
        movement_block: %MovementBlock{position: {1.0, 2.0, 3.0, 0.5}}
      }

      assert {^character, [%UpdateObject{object: %Object{guid: ^player_guid}}]} = Login.worldport_updates(character)
    end
  end

  defp character(opts) do
    %Character{
      object: %Object{guid: 6},
      player: %Player{flags: Keyword.get(opts, :player_flags, 0)},
      unit: %Unit{health: Keyword.fetch!(opts, :health), max_health: 100},
      internal: %Internal{companion: %Companion{kind: :guardian, status: {:suspended, 416, 688}}}
    }
  end
end
