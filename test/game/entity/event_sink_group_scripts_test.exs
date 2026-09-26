defmodule ThistleTea.Game.Entity.EventSinkGroupScriptsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.CreatureGroup.Member
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.CreatureGroups
  alias ThistleTea.Game.World.System.Party
  alias ThistleTea.Game.WorldRef

  setup [:world_and_owner]

  describe "emit/3" do
    test "starts once on the explicit source owner, leader, and fellow group member", %{world: world, owner: owner} do
      [leader, source, member] = Enum.map(1..3, &mob(world, &1))
      other_world = WorldRef.instance(world.map_id, world.instance_id + 1)
      other = mob(other_world, 3)

      Enum.each([leader, source, member, other], fn mob ->
        Entity.register(mob.object.guid)
        CreatureGroups.register(mob, self())
      end)

      on_exit(fn -> CreatureGroups.stop_world(other_world) end)
      CreatureGroups.join(world, source.object.guid, leader.object.guid, %Member{}, self())
      CreatureGroups.join(world, member.object.guid, leader.object.guid, %Member{}, self())
      steps = [%ScriptStep{command: :set_home_position, datalong: 1, delay_ms: 1_000}]
      effect = %Effects.StartGroupScript{steps: steps, target_guid: 99}
      assert EventSink.emit(source, effect, Context.new(owner)) == source

      assert_receive {:owner, {:"$gen_cast", {:start_script, ^steps, 99, ^world}}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, 99, ^world}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, 99, ^world}}
      refute_receive {:"$gen_cast", {:start_script, _, _, _}}
      assert MobServer.handle_cast({:start_script, steps, 99, world}, other) == {:noreply, other}
    end

    test "an ungrouped source still runs its script without registry lookup", %{world: world, owner: owner} do
      source = mob(world, 1)
      steps = [%ScriptStep{command: :stand_state, datalong: 1}]
      EventSink.emit(source, %Effects.StartGroupScript{steps: steps, target_guid: nil}, Context.new(owner))
      assert_receive {:owner, {:"$gen_cast", {:start_script, ^steps, 0, ^world}}}
      refute_receive {:"$gen_cast", {:start_script, _, _, _}}
    end

    test "includes raid members across subgroups while delivery retains the source world", %{world: world, owner: owner} do
      source = character(world)
      member = character(WorldRef.instance(world.map_id, world.instance_id + 1))
      offline = character(world)
      Entity.register(source.object.guid)
      Entity.register(member.object.guid)

      on_exit(fn ->
        Enum.each([source, member, offline], &Party.leave(&1.object.guid))
      end)

      for invited <- [member, offline] do
        :ok = Party.invite(source.object.guid, "Source", invited.object.guid)
        {:ok, _} = Party.accept(invited.object.guid, "Member")
      end

      {:ok, _} = Party.convert_raid(source.object.guid)
      {:ok, _} = Party.change_subgroup(source.object.guid, member.object.guid, 7)
      steps = [%ScriptStep{command: :stand_state, datalong: 1}]
      EventSink.emit(source, %Effects.StartGroupScript{steps: steps, target_guid: 99}, Context.new(owner))
      assert_receive {:owner, {:"$gen_cast", {:start_script, ^steps, 99, ^world}}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, 99, ^world}}
      refute_receive {:"$gen_cast", {:start_script, _, _, _}}
      state = %State{character: member}
      assert PlayerServer.handle_cast({:start_script, steps, 99, world}, state) == {:noreply, state}
    end
  end

  defp world_and_owner(_context) do
    world = WorldRef.instance(329, System.unique_integer([:positive]))
    parent = self()

    owner =
      spawn_link(fn ->
        receive do
          message -> send(parent, {:owner, message})
        end
      end)

    on_exit(fn ->
      CreatureGroups.stop_world(world)
      if Process.alive?(owner), do: Process.exit(owner, :kill)
    end)

    %{world: world, owner: owner}
  end

  defp mob(world, db_guid) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 1, System.unique_integer([:positive]))},
      unit: %Unit{health: 100},
      internal: %Internal{world: world, creature: %Creature{db_guid: db_guid}}
    }
  end

  defp character(world) do
    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      internal: %Internal{world: world}
    }
  end
end
