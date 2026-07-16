defmodule ThistleTea.Game.Network.Message.CmsgAreatriggerTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.CmsgAreatrigger
  alias ThistleTea.Game.Network.Message.SmsgAreaTriggerMessage
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  @moduletag :vmangos_db

  @entrance_id 2230
  @exit_id 2226
  @entrance_position {1818.4, -4427.26, -10.4478, 0.0}
  @exit_position {2.58019, -0.013587, -13.3668, 0.0}

  describe "handle/2" do
    test "rejects players below Ragefire Chasm's minimum level" do
      state = state(7, WorldRef.open(1), @entrance_position)

      assert CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @entrance_id}, state) == state

      assert_receive {:"$gen_cast", {:send_packet, %SmsgAreaTriggerMessage{message: message}}}
      assert message == "You must be at least level 8 to enter."
      refute_receive {:"$gen_cast", {:start_teleport, _, _, _, _, _}}
    end

    test "gives party members the same Ragefire Chasm copy" do
      first_guid = unique_guid()
      second_guid = unique_guid()

      assert :ok = PartySystem.invite(first_guid, "First", second_guid)
      assert {:ok, _group} = PartySystem.accept(second_guid, "Second")

      first_state = state(8, WorldRef.open(1), @entrance_position, first_guid)
      second_state = state(8, WorldRef.open(1), @entrance_position, second_guid)

      CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @entrance_id}, first_state)
      CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @entrance_id}, second_state)

      assert_receive {:"$gen_cast", {:start_teleport, 0.797643, -8.23429, -15.5288, 4.71239, first_world}}
      assert_receive {:"$gen_cast", {:start_teleport, 0.797643, -8.23429, -15.5288, 4.71239, second_world}}
      assert first_world == second_world
      assert %WorldRef{map_id: 389, instance_id: instance_id} = first_world
      assert is_integer(instance_id)

      InstanceSystem.leave(first_guid, first_world)
      InstanceSystem.leave(second_guid, second_world)
      assert {:ok, _outcome} = PartySystem.leave(first_guid)
    end

    test "gives solo players separate Ragefire Chasm copies" do
      first_state = state(8, WorldRef.open(1), @entrance_position)
      second_state = state(8, WorldRef.open(1), @entrance_position)

      CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @entrance_id}, first_state)
      CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @entrance_id}, second_state)

      assert_receive {:"$gen_cast", {:start_teleport, _, _, _, _, first_world}}
      assert_receive {:"$gen_cast", {:start_teleport, _, _, _, _, second_world}}
      refute first_world == second_world

      InstanceSystem.leave(first_state.guid, first_world)
      InstanceSystem.leave(second_state.guid, second_world)
    end

    test "routes the Ragefire Chasm exit back to the open world" do
      guid = unique_guid()
      {:ok, instance_world} = InstanceSystem.enter(389, guid)
      state = state(8, instance_world, @exit_position, guid)

      CmsgAreatrigger.handle(%CmsgAreatrigger{trigger_id: @exit_id}, state)

      assert_receive {:"$gen_cast", {:start_teleport, 1814.99, -4419.23, -18.8151, 1.91986, destination_world}}

      assert destination_world == WorldRef.open(1)
      InstanceSystem.leave(guid, instance_world)
    end
  end

  defp state(level, world, position, guid \\ unique_guid()) do
    %{
      ready: true,
      guid: guid,
      character: %Character{
        unit: %Unit{level: level},
        movement_block: %MovementBlock{position: position},
        internal: %Internal{world: world}
      }
    }
  end

  defp unique_guid, do: System.unique_integer([:positive])
end
