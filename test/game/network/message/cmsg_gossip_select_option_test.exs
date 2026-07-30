defmodule ThistleTea.Game.Network.Message.CmsgGossipSelectOptionTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Network.Message.CmsgGossipSelectOption
  alias ThistleTea.Game.Network.Message.SmsgGossipComplete
  alias ThistleTea.Game.World.Loader.Gossip.Option

  describe "handle/2" do
    test "dispatches a taxi gossip script to the player owner" do
      player_guid = System.unique_integer([:positive, :monotonic])
      {:ok, _owner} = Entity.register(player_guid)

      option = %Option{
        id: 0,
        option_id: 1,
        action_menu_id: -1,
        taxi_path_steps: [%ScriptStep{command: :send_taxi_path, datalong: 315}]
      }

      character = %Character{
        object: %Object{guid: player_guid},
        unit: %Unit{},
        internal: %Internal{}
      }

      state = %{character: character, gossip_menu_options: [option]}
      message = %CmsgGossipSelectOption{guid: 1, gossip_list_id: 0}

      assert %{gossip_menu_options: []} = CmsgGossipSelectOption.handle(message, state)
      assert_receive {:send_taxi_path, 315}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
    end
  end
end
