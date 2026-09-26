defmodule ThistleTea.Game.Player.AttackingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.TargetRef
  alias ThistleTea.Game.Entity.Server.Player
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  setup [:selected_target]

  describe "start_selected/2" do
    test "arrival uses client selection even when combat has cleared the attack field", %{state: state, target: target} do
      assert state.character.unit.target == 0
      assert EventSink.emit(state.character, Effects.attack_start(target), Context.new(self())) == state.character
      assert_receive {:force_attack, ^target} = command
      assert {:noreply, started} = Player.handle_info(command, state)
      assert started.character.internal.blackboard.combat.auto_attacking
      assert started.character.internal.blackboard.combat.auto_attack_target == target
      assert started.character.unit.target == target.guid
      Process.cancel_timer(started.player_tick_ref)
    end

    test "changing or clearing selection prevents a late attack", %{state: state, target: target} do
      for selection <- [0, nil, state.guid] do
        changed = %{state | target: selection}
        assert {:noreply, ^changed} = Player.handle_info({:force_attack, target}, changed)
      end
    end

    test "death, despawn, respawn and world transfer invalidate the arrival target", %{state: state, target: target} do
      original = Metadata.get(target.guid)

      for metadata <- [%{original | alive?: false}, %{original | incarnation_id: 8}, nil] do
        if metadata, do: Metadata.put(target.guid, metadata), else: Metadata.delete(target.guid)
        assert {:noreply, ^state} = Player.handle_info({:force_attack, target}, state)
      end

      Metadata.put(target.guid, original)
      SpatialHash.update(:mobs, target.guid, WorldRef.instance(0, 77), 1.0, 0.0, 0.0)
      assert {:noreply, ^state} = Player.handle_info({:force_attack, target}, state)
    end

    test "a dead player cannot begin the queued attack", %{state: state, target: target} do
      dead = %{state | character: %{state.character | unit: %{state.character.unit | health: 0}}}
      assert {:noreply, ^dead} = Player.handle_info({:force_attack, target}, dead)
    end
  end

  defp selected_target(_context) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    target_guid = Guid.runtime(:mob, 1)
    alliance = %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}

    wolf = %FactionTemplate{
      id: 32,
      faction: 29,
      flags: 16,
      faction_group: 0,
      friend_group: 0,
      enemy_group: 0,
      enemies_0: 28
    }

    Metadata.put(guid, %{faction_template: alliance, attacker_count: 0})

    Metadata.put(target_guid, %{
      faction_template: wolf,
      faction_can_have_reputation?: false,
      alive?: true,
      incarnation_id: 7,
      unit_flags: 0
    })

    SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)

    on_exit(fn ->
      Metadata.delete(guid)
      Metadata.delete(target_guid)
      SpatialHash.remove(:mobs, target_guid)
    end)

    character = %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, target: 0},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{
      state: %State{guid: guid, target: target_guid, character: character},
      target: %TargetRef{guid: target_guid, incarnation_id: 7}
    }
  end
end
