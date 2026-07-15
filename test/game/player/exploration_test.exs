defmodule ThistleTea.Game.Player.ExplorationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Network.Message.SmsgExplorationExperience
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Player.Exploration
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Loader.Exploration, as: ExplorationLoader

  @character_id 2_000_000

  setup do
    on_exit(fn -> :ets.delete(CharacterStore, @character_id) end)
  end

  describe "check_movement/2" do
    test "throttles terrain probes between movement checks" do
      state = %{ready: false, next_exploration_check_at: nil}

      state = Exploration.check_movement(state, 1_000)

      assert state.next_exploration_check_at == 2_000
      assert Exploration.check_movement(state, 1_999) == state
    end
  end

  describe "discover_area/2" do
    test "persists and sends the first discovery but not repeats" do
      :ets.insert(
        ExplorationLoader,
        {{:area, 9}, %AreaTable{id: 9, area_bit: 125, exploration_level: 0, name: "Northshire Valley"}}
      )

      state = %{guid: @character_id, character: character()}
      state = Exploration.discover_area(state, 9)

      assert state.character.player.explored_zones == CharacterStore.get(@character_id).player.explored_zones
      assert_receive {:"$gen_cast", {:send_packet, %UpdateObject{update_type: :values}}}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgExplorationExperience{area_id: 9, experience: 0}}}
      assert Exploration.discover_area(state, 9) == state
      refute_receive {:"$gen_cast", _message}
    end
  end

  defp character do
    %Character{
      id: @character_id,
      unit: %Unit{level: 1},
      player: %Player{},
      internal: %Internal{}
    }
  end
end
