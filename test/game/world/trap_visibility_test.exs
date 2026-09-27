defmodule ThistleTea.Game.World.TrapVisibilityTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Visibility
  alias ThistleTea.Game.WorldRef

  setup [:trap]

  describe "can_see?/2" do
    test "hides hostile traps but preserves their owner's and allies' sight", context do
      %{state: state, trap: trap, owner: owner} = context
      refute Visibility.can_see?(state, trap)
      ally = %{state | guid: owner, character: %{state.character | object: %Object{guid: owner}}}
      assert Visibility.can_see?(ally, trap)
      Metadata.update(owner, %{faction_template: alliance()})
      assert Visibility.can_see?(state, trap)
      Metadata.update(trap, %{go_spawned?: false})
      refute Visibility.can_see?(state, trap)
    end

    test "requires trap detection rather than ordinary stealth or invisibility", %{state: state, trap: trap} do
      for {type, misc, expected} <- [
            {:mod_stealth_detect, 1, false},
            {:mod_invisibility_detect, 0, false},
            {:mod_invisibility, 3, false},
            {:mod_invisibility_detect, 3, true}
          ] do
        aura = %Aura{type: type, misc_value: misc, amount: 0}
        viewer = %{state.character | unit: %{state.character.unit | auras: [%Holder{auras: [aura]}]}}
        assert Visibility.can_see?(%{state | character: viewer}, trap) == expected
      end
    end

    test "uses unowned trap faction and treats an absent faction as hostile", %{state: state, trap: trap} do
      Metadata.update(trap, %{owner_guid: nil, faction_template_id: nil})
      refute Visibility.can_see?(state, trap)
      Metadata.update(trap, %{faction_template_id: 1, faction_template: alliance()})
      assert Visibility.can_see?(state, trap)
      Metadata.update(trap, %{go_trap_stealthed?: false, faction_template: horde()})
      assert Visibility.can_see?(state, trap)
    end
  end

  describe "stealth_detection_tick/2" do
    test "reevaluates owner hostility and detection without moving either observer", context do
      %{state: state, trap: trap, owner: owner} = context
      Entity.register(trap)
      state = %{state | tracked_entities: MapSet.new([trap])} |> tick()
      refute Visibility.tracked?(state, trap)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^trap}, force: true}}

      Metadata.update(owner, %{faction_template: alliance()})
      tick(state)
      guid = state.guid
      assert_receive {:"$gen_cast", {:send_update_to, ^guid}}

      Metadata.update(owner, %{faction_template: horde()})
      aura = %Aura{type: :mod_invisibility_detect, misc_value: 3, amount: 300}
      character = %{state.character | unit: %{state.character.unit | auras: [%Holder{auras: [aura]}]}}
      tick(%{state | character: character})
      assert_receive {:"$gen_cast", {:send_update_to, ^guid}}

      state = %{state | tracked_entities: MapSet.new([trap])} |> tick()
      refute Visibility.tracked?(state, trap)
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgDestroyObject{guid: ^trap}, force: true}}
      assert Visibility.leave_player(state).game_object_guids == []
    end
  end

  describe "handle_events/2" do
    test "retains hidden candidates until their object leaves the visibility cells", %{state: state, trap: trap} do
      event = %Group.Event{
        type: :joined,
        key: Visibility.cell_key({state.character.internal.world, 0, 0}),
        meta: %{guid: trap, type: :game_object}
      }

      joined = Visibility.handle_events(%{state | game_object_guids: []}, [event])
      assert joined.game_object_guids == [trap]
      refute Visibility.tracked?(joined, trap)
      left = Visibility.handle_events(joined, [%{event | type: :left}])
      assert left.game_object_guids == []
    end
  end

  defp tick(state) do
    state = Visibility.schedule_stealth_detection(state)
    Process.cancel_timer(state.stealth_detection_ref)
    updated = Visibility.stealth_detection_tick(state, state.stealth_detection_ref)
    Process.cancel_timer(updated.stealth_detection_ref)
    updated
  end

  defp trap(_context) do
    viewer = System.unique_integer([:positive, :monotonic])
    owner = System.unique_integer([:positive, :monotonic])
    trap = Guid.runtime(:game_object, 950_201)
    world = WorldRef.open(999)

    character = %Character{
      object: %Object{guid: viewer},
      unit: %Unit{health: 100, level: 60, auras: []},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    Metadata.put(viewer, %{faction_template: alliance()})
    Metadata.put(owner, %{faction_template: horde()})
    Metadata.put(trap, %{owner_guid: owner, go_spawned?: true, go_trap_stealthed?: true})
    World.SpatialHash.insert(:game_objects, trap, world, 4.0, 0.0, 0.0)

    on_exit(fn ->
      for guid <- [viewer, owner, trap], do: Metadata.delete(guid)
      World.SpatialHash.remove(:game_objects, trap)
    end)

    %{
      owner: owner,
      trap: trap,
      state: %State{
        guid: viewer,
        character: character,
        visibility_cells: MapSet.new([{world, 0, 0}]),
        game_object_guids: [trap],
        cell_activator: nil
      }
    }
  end

  defp alliance, do: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
  defp horde, do: %FactionTemplate{id: 2, faction: 2, faction_group: 5, friend_group: 4, enemy_group: 10}
end
