defmodule ThistleTea.Game.World.VisibilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.Visibility

  describe "enter_player/1" do
    test "joins current cell and initializes visible entity lists" do
      self_guid = Guid.from_low_guid(:player, unique_low())
      other_guid = Guid.from_low_guid(:player, unique_low())
      mob_guid = Guid.from_low_guid(:mob, unique_low(), unique_low())
      cell = {0, 0, 0}

      other_pid = start_member(cell, %{guid: other_guid, type: :player})
      mob_pid = start_member(cell, %{guid: mob_guid, type: :mob})

      state =
        %{guid: self_guid, character: entity(self_guid), tracked_entities: MapSet.new()}
        |> Visibility.enter_player()

      assert self_guid in state.player_guids
      assert other_guid in state.player_guids
      assert mob_guid in state.mob_guids
      assert MapSet.member?(state.visibility_cells, cell)
      assert state.character.internal.visibility_cell == cell

      Visibility.leave_player(state)
      stop_member(other_pid)
      stop_member(mob_pid)
    end
  end

  describe "handle_events/2" do
    test "tracks joined players in visible cells" do
      guid = Guid.from_low_guid(:player, unique_low())
      state = %{guid: Guid.from_low_guid(:player, unique_low()), visibility_cells: MapSet.new([{0, 0, 0}])}

      event = %Group.Event{
        type: :joined,
        key: Visibility.cell_key({0, 0, 0}),
        meta: %{guid: guid, type: :player}
      }

      state = Visibility.handle_events(state, [event])

      assert guid in state.player_guids
    end

    test "destroys tracked entities that leave visible cells" do
      guid = Guid.from_low_guid(:player, unique_low())

      state = %{
        guid: Guid.from_low_guid(:player, unique_low()),
        visibility_cells: MapSet.new([{0, 0, 0}]),
        tracked_entities: MapSet.new([guid]),
        player_guids: [guid]
      }

      event = %Group.Event{
        type: :left,
        key: Visibility.cell_key({0, 0, 0}),
        meta: %{guid: guid, type: :player}
      }

      state = Visibility.handle_events(state, [event])

      refute MapSet.member?(state.tracked_entities, guid)
      refute guid in state.player_guids
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^guid}}}
    end

    test "keeps tracked entities that move between still-visible cells" do
      guid = Guid.from_low_guid(:player, unique_low())
      SpatialHash.insert(:players, guid, 0, 125, 0, 0)

      state = %{
        guid: Guid.from_low_guid(:player, unique_low()),
        visibility_cells: MapSet.new([{0, 0, 0}, {0, 1, 0}]),
        tracked_entities: MapSet.new([guid]),
        player_guids: [guid]
      }

      event = %Group.Event{
        type: :left,
        key: Visibility.cell_key({0, 0, 0}),
        meta: %{guid: guid, type: :player}
      }

      state = Visibility.handle_events(state, [event])

      assert MapSet.member?(state.tracked_entities, guid)
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}}}

      SpatialHash.remove(:players, guid)
    end
  end

  defp start_member(cell, meta) do
    parent = self()

    pid =
      spawn_link(fn ->
        :ok = Group.join(Visibility.group_name(), Visibility.cell_key(cell), meta)
        send(parent, {:joined, self()})

        receive do
          :stop -> Group.leave(Visibility.group_name(), Visibility.cell_key(cell))
        end
      end)

    assert_receive {:joined, ^pid}
    pid
  end

  defp stop_member(pid) do
    send(pid, :stop)
  end

  defp entity(guid) do
    %{
      object: %Object{guid: guid},
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp unique_low do
    rem(System.unique_integer([:positive]), 0x00FFFFFF)
  end
end
