defmodule ThistleTea.Game.World.Entity.Player.TrapDisarmingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Profession.Lock
  alias ThistleTea.Game.Core.Profession.Lock.Requirement
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Gathering
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: TemplateLoader
  alias ThistleTea.Game.World.Loader.Lock, as: LockLoader
  alias ThistleTea.Game.World.Metadata

  @moduletag :namigator_maps
  @entry 950_211
  @lock 950_212

  setup [:trap]

  describe "complete/5" do
    test "disarms a detected trap without opening loot or awarding a skill", context do
      %{state: state, guid: guid, pid: pid, spell: spell} = context
      assert {:error, :bad_targets} = Gathering.context(state, spell, Target.object(guid), nil)
      assert Gathering.complete(state, guid, spell, nil) == state
      assert Process.alive?(pid)

      state = detect(state)
      assert {:ok, %Lock{}, nil} = Gathering.context(state, spell, Target.object(guid), nil)
      monitor = Process.monitor(pid)
      result = Gathering.complete(state, guid, spell, nil, [Effects.spell_cast_result(spell.id)])
      assert result.loot_guid == nil
      assert result.character.player.skills == state.character.player.skills
      assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 0}}}
      assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1_000
      assert Entity.pid(guid) == nil
      assert Metadata.get(guid) == nil
      refute_receive {:"$gen_cast", {:send_packet, %Message.SmsgLootResponse{}}}
    end

    test "rechecks detection, range, world, and lock type before removing the target", context do
      %{state: state, guid: guid, pid: pid, spell: spell} = context
      seen = detect(state)
      assert {:ok, %Lock{}, nil} = Gathering.context(seen, spell, Target.object(guid), nil)

      moved = %{seen.character | movement_block: %MovementBlock{position: {16_290.0, 16_250.1, 69.44, 0.0}}}
      foreign = %{seen.character | internal: %{seen.character.internal | world: WorldRef.open(0)}}
      wrong = %{spell | effects: [%Effect{type: :open_lock, misc_value: 1, base_points: 199}]}

      for {attempt, cast} <- [
            {state, spell},
            {%{seen | character: moved}, spell},
            {%{seen | character: foreign}, spell},
            {seen, wrong}
          ] do
        assert Gathering.complete(attempt, guid, cast, nil) == attempt
        assert Process.alive?(pid)
        assert :sys.get_state(pid).internal.gathering.opened_by == %{}
      end
    end
  end

  defp detect(state) do
    holder = %Holder{
      spell: %Spell{id: 2836},
      auras: [%Aura{type: :mod_invisibility_detect, misc_value: 3, amount: 300}]
    }

    %{state | character: %{state.character | unit: %{state.character.unit | auras: [holder]}}}
  end

  defp trap(_context) do
    template = %GameObjectTemplate{
      entry: @entry,
      type: 6,
      size: 1.0,
      flags: 0,
      faction: 0,
      data: [@lock, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    }

    TemplateLoader.put(template)
    :ets.insert(LockLoader, {@lock, %Lock{id: @lock, requirements: [%Requirement{type: :skill, index: 4}]}})
    world = WorldRef.open(451)
    object = GameObject.build_summoned(template, world, {16_303.2, 16_254.1, 69.44, 0.0})
    {:ok, pid} = World.start_incarnation(object)
    id = System.unique_integer([:positive, :monotonic])

    character = %Character{
      id: id,
      player: %Player{skills: %{}},
      object: %Object{guid: id},
      unit: %Unit{health: 100, max_health: 100, level: 50, auras: []},
      internal: %Internal{world: world},
      movement_block: %MovementBlock{position: {16_303.2, 16_250.1, 69.44, 0.0}}
    }

    on_exit(fn ->
      World.stop_entity(object.object.guid)
      :ets.delete(TemplateLoader, @entry)
      :ets.delete(LockLoader, @lock)
      :ets.delete(CharacterStore, id)
      Metadata.delete(id)
    end)

    %{
      state: %State{guid: id, character: character},
      guid: object.object.guid,
      pid: pid,
      spell: %Spell{id: 1842, effects: [%Effect{type: :open_lock, misc_value: 4, base_points: 199}]}
    }
  end
end
