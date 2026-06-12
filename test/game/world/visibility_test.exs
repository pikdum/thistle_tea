defmodule ThistleTea.Game.World.VisibilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.CellActivator
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
        %{guid: self_guid, character: entity(self_guid), tracked_entities: MapSet.new(), cell_activator: nil}
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

    test "activates visible cells through the configured cell activator" do
      parent = self()
      loader = fn cell -> send(parent, {:activated, cell}) end
      name = :"visibility_cell_activator_test_#{System.unique_integer([:positive])}"
      start_supervised!({CellActivator, name: name, loader: loader})

      self_guid = Guid.from_low_guid(:player, unique_low())

      state =
        %{
          guid: self_guid,
          character: entity(self_guid),
          tracked_entities: MapSet.new(),
          cell_activator: name
        }
        |> Visibility.enter_player()

      assert_receive {:activated, {0, 0, 0}}
      Visibility.leave_player(state)
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
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^guid}, force: true}}
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
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{}, _opts}}

      SpatialHash.remove(:players, guid)
    end
  end

  describe "ghost visibility" do
    test "resync hides living mobs from ghosts and reveals spirit healers" do
      self_guid = Guid.from_low_guid(:player, unique_low())
      mob_guid = Guid.from_low_guid(:mob, unique_low(), unique_low())
      healer_guid = Guid.from_low_guid(:mob, unique_low(), unique_low())
      cell = {0, 0, 0}

      mob_pid = start_member(cell, %{guid: mob_guid, type: :mob})
      healer_pid = start_member(cell, %{guid: healer_guid, type: :mob})
      Metadata.put(mob_guid, %{alive?: true})
      Metadata.put(healer_guid, %{alive?: true, spirit_service?: true})
      Entity.register(mob_guid)
      Entity.register(healer_guid)

      state = %{
        guid: self_guid,
        character: character(self_guid, ghost?: true),
        visibility_cells: MapSet.new([cell]),
        tracked_entities: MapSet.new([mob_guid]),
        cell_activator: nil
      }

      state = Visibility.resync_player(state)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^mob_guid}, force: true}}
      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}
      refute MapSet.member?(state.tracked_entities, mob_guid)
      assert mob_guid in state.mob_guids

      Entity.unregister(mob_guid)
      Entity.unregister(healer_guid)
      Metadata.delete(mob_guid)
      Metadata.delete(healer_guid)
      stop_member(mob_pid)
      stop_member(healer_pid)
    end

    test "living players do not request creates for spirit healers or ghost players" do
      self_guid = Guid.from_low_guid(:player, unique_low())
      healer_guid = Guid.from_low_guid(:mob, unique_low(), unique_low())
      ghost_guid = Guid.from_low_guid(:player, unique_low())
      cell = {0, 0, 0}

      healer_pid = start_member(cell, %{guid: healer_guid, type: :mob})
      ghost_pid = start_member(cell, %{guid: ghost_guid, type: :player})
      Metadata.put(healer_guid, %{alive?: true, spirit_service?: true})
      Metadata.put(ghost_guid, %{alive?: false, ghost?: true})
      Entity.register(healer_guid)
      Entity.register(ghost_guid)

      state = %{
        guid: self_guid,
        character: character(self_guid, ghost?: false),
        visibility_cells: MapSet.new([cell]),
        tracked_entities: MapSet.new(),
        cell_activator: nil
      }

      state = Visibility.resync_player(state)

      refute_receive {:"$gen_cast", {:send_update_to, _}}
      assert ghost_guid in state.player_guids

      Entity.unregister(healer_guid)
      Entity.unregister(ghost_guid)
      Metadata.delete(healer_guid)
      Metadata.delete(ghost_guid)
      stop_member(healer_pid)
      stop_member(ghost_pid)
    end

    test "reevaluate_entity destroys tracked entities that became invisible" do
      self_guid = Guid.from_low_guid(:player, unique_low())
      ghost_guid = Guid.from_low_guid(:player, unique_low())

      SpatialHash.insert(:players, ghost_guid, 0, 0, 0, 0)
      Metadata.put(ghost_guid, %{alive?: false, ghost?: true})

      state = %{
        guid: self_guid,
        character: character(self_guid, ghost?: false),
        visibility_cells: MapSet.new([{0, 0, 0}]),
        tracked_entities: MapSet.new([ghost_guid])
      }

      Visibility.reevaluate_entity(state, ghost_guid)

      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^ghost_guid}, force: true}}

      SpatialHash.remove(:players, ghost_guid)
      Metadata.delete(ghost_guid)
    end

    test "reevaluate_entity requests creates for entities that became visible" do
      self_guid = Guid.from_low_guid(:player, unique_low())
      revived_guid = Guid.from_low_guid(:player, unique_low())

      SpatialHash.insert(:players, revived_guid, 0, 0, 0, 0)
      Metadata.put(revived_guid, %{alive?: true, ghost?: false})
      Entity.register(revived_guid)

      state = %{
        guid: self_guid,
        character: character(self_guid, ghost?: false),
        visibility_cells: MapSet.new([{0, 0, 0}]),
        tracked_entities: MapSet.new()
      }

      Visibility.reevaluate_entity(state, revived_guid)

      assert_receive {:"$gen_cast", {:send_update_to, ^self_guid}}

      Entity.unregister(revived_guid)
      SpatialHash.remove(:players, revived_guid)
      Metadata.delete(revived_guid)
    end
  end

  defp character(guid, opts) do
    flags = if Keyword.get(opts, :ghost?, false), do: 0x10, else: 0

    %Character{
      object: %Object{guid: guid},
      unit: %Unit{},
      player: %Player{flags: flags},
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
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
