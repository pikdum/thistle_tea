defmodule ThistleTea.Game.Entity.Logic.ControlMovementTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BehaviorRunner
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Confusion
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Navigation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Random
  alias ThistleTea.Game.Entity.Logic.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.ControlMovement
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Fear
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.NavigationResolver
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.Message.MsgMove
  alias ThistleTea.Game.Player.Movement, as: PlayerMovement
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "reconcile/4" do
    test "replacing the active fear source restarts navigation without granting control", %{character: character} do
      first = holder(1, :mod_fear)
      second = %{holder(2, :mod_fear) | caster_guid: 3, applied_at: 500}
      {character, _} = change(character, [first], 0)
      character = step(character, 0)
      {character, events} = change(character, [first, second], 500)
      assert controls(events) == []
      assert Movement.moving?(character, 500)
      {character, events} = change(character, [second], 1_000)
      assert controls(events) == []
      assert character.movement_block.position == {7.0, 0.0, 0.0, 0.0}
      refute Movement.moving?(character, 1_000)
      assert character.internal.blackboard.fear.next_move_at == 1_000
      assert Fear.source_guid(character) == 3
    end

    test "revokes control until the last overlapping effect ends", %{character: character} do
      fear = holder(1, :mod_fear)
      confusion = holder(2, :mod_confuse)
      {character, events} = change(character, [fear], 0)
      assert [%Effects.ClientControlChanged{allow_movement?: false}] = controls(events)
      assert Bitwise.band(character.unit.flags, 0x00800000) != 0
      {character, events} = change(character, [fear, confusion], 1)
      assert controls(events) == []
      assert ControlMovement.mode(character) == :confusion
      assert character.internal.blackboard.fear == nil
      assert Bitwise.band(character.unit.flags, 0x00C00000) == 0x00C00000
      {character, events} = change(character, [fear], 2)
      assert controls(events) == []
      assert ControlMovement.mode(character) == :fear
      assert character.internal.blackboard.confusion == nil
      {character, events} = change(character, [], 3)
      assert [%Effects.ClientControlChanged{allow_movement?: true}] = controls(events)
      refute ControlMovement.active?(character)
      assert Bitwise.band(character.unit.flags, 0x00C00000) == 0
      assert character.internal.running
    end

    test "fleeing prevention restores control unless confusion remains", %{character: character} do
      fear = holder(1, :mod_fear)
      prevention = holder(2, :prevent_fleeing)
      {character, _} = change(character, [fear], 0)
      {character, events} = change(character, [fear, prevention], 1)
      assert [%Effects.ClientControlChanged{allow_movement?: true}] = controls(events)
      assert character.internal.blackboard.fear == nil
      {character, events} = change(character, [fear], 2)
      assert [%Effects.ClientControlChanged{allow_movement?: false}] = controls(events)
      {character, events} = change(character, [fear, prevention, holder(3, :mod_confuse)], 3)
      assert controls(events) == []
      assert ControlMovement.mode(character) == :confusion
    end

    test "stops at the current spline position and discards pending movement", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_fear)], 0)
      character = step(character, 0)
      assert [%Effects.MonsterMove{} | _] = character.internal.events
      {character, events} = change(character, [], 1_000)
      assert character.movement_block.position == {7.0, 0.0, 0.0, 0.0}
      assert character.movement_block.spline_nodes == []
      assert character.internal.movement_start_time == nil
      assert character.internal.navigation_intents == []
      refute Enum.any?(character.internal.events, &is_struct(&1, Effects.MonsterMove))
      assert Enum.any?(events, &is_struct(&1, Effects.MovementStopped))
      assert [%Effects.ClientControlChanged{allow_movement?: true}] = controls(events)
    end

    test "roots pause movement without restoring client control", %{character: character} do
      fear = holder(1, :mod_fear)
      {character, _} = change(character, [fear], 0)
      character = step(character, 0)
      {character, events} = change(character, [fear, holder(2, :mod_root)], 500)
      assert controls(events) == []
      refute Movement.moving?(character, 500)
      assert {{:running, 500, :fear}, _} = BehaviorRunner.tick(PlayerBT.tree(), character, context(500))
      {character, events} = change(character, [fear], 600)
      assert controls(events) == []
      {_, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(2_001))
      {_, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(3_501))
      assert character.internal.navigation_intents != []
    end

    test "death clears control, flags, and navigation", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_fear)], 0)
      character = character |> step(0) |> Core.take_damage(100, 500)
      assert character.unit.health == 0
      refute ControlMovement.active?(character)
      assert character.internal.blackboard.fear == nil
      assert character.internal.movement_start_time == nil
      assert Enum.any?(character.internal.events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
    end
  end

  describe "tick/3" do
    test "bounds confusion even when a navigation sample escapes its circle", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_confuse)], 0)
      navigation = Navigation.new(%{{0, {0.0, 0.0, 0.0}, 4.0} => {30.0, 0.0, 0.0}})
      {_, character} = BehaviorRunner.tick(PlayerBT.tree(), character, Context.new(0, navigation: navigation))
      character = NavigationResolver.resolve(character, 0, fn _, _, destination, _ -> [destination] end)
      assert character.movement_block.spline_nodes == [{4.0, 0.0, 0.0}]
    end

    test "rejects detours that leave the confusion circle", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_confuse)], 0)
      {_, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(0))

      character =
        NavigationResolver.resolve(character, 0, fn _, _, destination, _ -> [{4.1, 0.0, 0.0}, destination] end)

      refute Movement.moving?(character, 0)
      assert character.movement_block.spline_nodes == []
      assert {{:running, 500, :confusion}, _} = BehaviorRunner.tick(PlayerBT.tree(), character, context(100))
    end

    test "the player tree runs fear paths and pauses after arrival", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_fear)], 0)
      character = step(character, 0)
      assert character.movement_block.duration == 2_000
      assert character.internal.running
      assert Movement.moving?(character, 1_000)
      character = Movement.sync_position(character, 2_001)
      assert {{:running, 800, :fear}, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(2_001))
      assert character.internal.blackboard.fear.next_move_at == 2_801
    end

    test "confusion walks around a stable anchor and restores running", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_confuse)], 0)
      assert Confusion.request(character, 0) == {0, {0.0, 0.0, 0.0}, 4.0}
      character = step(character, 0)
      assert character.movement_block.duration == 1_000
      refute character.internal.running
      assert character.internal.blackboard.confusion.anchor == {0.0, 0.0, 0.0}
      character = Movement.sync_position(character, 1_001)
      assert {{:running, 500, :confusion}, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(1_001))
      assert Confusion.request(character, 1_500) == nil
      assert Confusion.request(character, 1_501) == {0, {0.0, 0.0, 0.0}, 4.0}
      {character, _} = change(character, [], 1_501)
      assert character.internal.running
      assert character.internal.blackboard.confusion == nil
    end

    test "failed navigation retries without a busy loop", %{character: character} do
      for {type, reason, delay} <- [{:mod_fear, :fear, 1_000}, {:mod_confuse, :confusion, 500}] do
        {character, _} = change(character, [holder(1, type)], 0)
        context = Context.new(0, random: Random.fixed(0.0))
        assert {{:running, ^delay, ^reason}, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context)
        assert character.internal.navigation_intents == []
      end
    end

    test "expiry restores control before another behavior runs", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_fear)], 0)
      {_, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(10_001))
      refute ControlMovement.active?(character)
      assert Enum.any?(character.internal.events, &match?(%Effects.ClientControlChanged{allow_movement?: true}, &1))
    end
  end

  describe "handle/2" do
    test "ordinary movement cannot move a corpse but permits a released ghost", %{character: character} do
      character = %{character | unit: %{character.unit | health: 0}}
      state = %State{guid: 1, ready: true, character: character}
      assert MsgMove.handle(%MsgMove{payload: <<1>>, opcode: 0xEE}, state) == state
      character = %{character | unit: %{character.unit | health: 1}, player: %{character.player | flags: 0x10}}
      assert PlayerMovement.accepts_input?(character)
    end

    test "possessed creatures reject input and notify the controller", %{character: character} do
      mob = %Mob{
        object: character.object,
        unit: %{character.unit | auras: [holder(9, :mod_possess)]},
        movement_block: character.movement_block,
        internal: %{character.internal | pet: %Pet{possessed?: true, owner_guid: 2}}
      }

      for type <- [:mod_fear, :mod_confuse] do
        {mob, events} = change(mob, [holder(9, :mod_possess), holder(1, type)], 0)
        assert [%Effects.ClientControlChanged{allow_movement?: false}] = controls(events)
        assert MobServer.handle_info({:controlled_move, 2, <<1>>, 0xEE}, mob) == {:noreply, mob}
        {_, events} = change(mob, [holder(9, :mod_possess)], 100)
        assert [%Effects.ClientControlChanged{allow_movement?: true}] = controls(events)
      end
    end

    test "rejects player movement packets throughout control and pauses", %{character: character} do
      for type <- [:mod_fear, :mod_confuse] do
        {character, _} = change(character, [holder(1, type)], 0)
        state = %State{guid: 1, character: character, ready: true}
        assert MsgMove.handle(%MsgMove{payload: <<1>>, opcode: 0xEE}, state) == state
        refute PlayerMovement.accepts_input?(character)
        {character, _} = change(character, [], 100)
        assert PlayerMovement.accepts_input?(character)
      end
    end
  end

  describe "restore/2" do
    test "rebuilds active control after behavior initialization", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_confuse)], 0)
      character = character |> BT.init(PlayerBT.tree()) |> ControlMovement.restore(100)
      assert character.internal.blackboard.confusion.anchor == {0.0, 0.0, 0.0}
      assert Enum.any?(character.internal.events, &match?(%Effects.ClientControlChanged{allow_movement?: false}, &1))
    end
  end

  describe "reset_navigation/1" do
    test "resumes forced movement with a negative monotonic clock", %{character: character} do
      for type <- [:mod_fear, :mod_confuse] do
        {character, _} = change(character, [holder(1, type)], -10_000)
        character = ControlMovement.reset_navigation(character)
        if type == :mod_confuse, do: assert(Confusion.request(character, -9_000) == {0, {0.0, 0.0, 0.0}, 4.0})

        assert {{:running, 0, :navigation}, character} =
                 BehaviorRunner.tick(PlayerBT.tree(), character, context(-9_000))

        assert character.internal.navigation_intents != []
      end
    end

    test "discards a movement projection queued before cancellation", %{character: character} do
      {character, _} = change(character, [holder(1, :mod_confuse)], 0)
      character = step(character, 0)
      assert Enum.any?(character.internal.events, &is_struct(&1, Effects.MonsterMove))
      character = character |> Movement.stop(500) |> ControlMovement.reset_navigation()
      refute Enum.any?(character.internal.events, &is_struct(&1, Effects.MonsterMove))
      assert Enum.any?(character.internal.events, &is_struct(&1, Effects.MovementStopped))
      assert character.internal.running
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 50, flags: 0, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, walk_speed: 2.5, run_speed: 7.0},
      internal: %Internal{world: WorldRef.open(0), running: true}
    }

    %{character: character}
  end

  defp holder(id, type) do
    %Holder{
      spell: %Spell{id: id, duration_ms: 10_000},
      caster_guid: 2,
      applied_at: 0,
      expires_at: 10_000,
      negative?: true,
      auras: [%AuraData{type: type}]
    }
  end

  defp change(character, holders, now),
    do: Aura.transition(character, %Change{holders: holders, cause: :applied, now: now})

  defp controls(events), do: Enum.filter(events, &is_struct(&1, Effects.ClientControlChanged))

  defp step(character, now) do
    {{:running, 0, :navigation}, character} = BehaviorRunner.tick(PlayerBT.tree(), character, context(now))
    NavigationResolver.resolve(character, now, fn _map, _start, destination, _opts -> [destination] end)
  end

  defp context(now) do
    navigation = %{Navigation.new(%{{0, {0.0, 0.0, 0.0}, 4.0} => {2.5, 0.0, 0.0}}) | fear_point: {14.0, 0.0, 0.0}}
    Context.new(now, navigation: navigation, random: Random.fixed(0.0))
  end
end
