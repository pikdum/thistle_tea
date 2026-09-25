defmodule ThistleTea.Game.Entity.Logic.AI.ScriptTargetsTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Condition
  alias ThistleTea.Game.Entity.Data.GameObject
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Data.ScriptStep
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  setup [:actors]

  describe "run/5" do
    test "orders initial swap, selection, final swap, and self targeting", %{actors: actors, guids: guids} do
      [source, target, source_victim, target_victim] = guids

      cases = [
        {:provided, 0, source, target},
        {:provided, 1, target, source},
        {:provided, 2, target, source},
        {:provided, 3, source, target},
        {:provided, 4, source, source},
        {:provided, 5, target, target},
        {:provided, 6, target, target},
        {:provided, 7, source, source},
        {:victim, 0, source, source_victim},
        {:victim, 1, target, target_victim},
        {:victim, 2, source_victim, source},
        {:victim, 3, target_victim, target},
        {:victim, 4, source, source},
        {:victim, 5, target, target},
        {:victim, 6, source_victim, source_victim},
        {:victim, 7, target_victim, target_victim}
      ]

      for {selector, flags, expected_owner, expected_target} <- cases do
        step = %{
          talk()
          | target_type: selector,
            swap_initial?: (flags &&& 1) != 0,
            swap_final?: (flags &&& 2) != 0,
            target_self?: (flags &&& 4) != 0
        }

        assert {^expected_owner, [%Effects.MonsterTalk{target_guid: ^expected_target}]} =
                 deliver(actors, source, [step], target)
      end
    end

    test "initial swaps defer selectors and conditions to the new source", %{
      actors: actors,
      guids: [source, target | _]
    } do
      step = %{
        talk()
        | swap_initial?: true,
          target_type: :victim,
          condition: %Condition{type: :is_player, swap_targets?: true}
      }

      {requested, _} = Script.run(actors[source], Blackboard.new(), [step], target, 0)
      assert [%Effects.ForwardScriptSteps{steps: [forwarded], source_guid: ^source}] = requested.internal.events
      refute forwarded.swap_initial?
      assert forwarded.target_type == :victim
      assert forwarded.condition == step.condition
      assert {^target, [%Effects.MonsterTalk{}]} = deliver(actors, source, [step], target)

      failing = %{step | condition: %Condition{type: :source_entry, value1: 999}}
      assert {^target, []} = deliver(actors, source, [failing], target)
    end

    test "conditions use the selected target even without a swap", %{
      actors: actors,
      guids: [source, target, victim | _]
    } do
      step = %{
        talk()
        | target_type: :victim,
          condition: %Condition{type: :source_entry, value1: Guid.entry(victim), swap_targets?: true}
      }

      assert {^source, [%Effects.MonsterTalk{target_guid: ^victim}]} = deliver(actors, source, [step], target)
    end

    test "a missing selector skips self-targeted commands", %{actors: actors, guids: [source, target | _]} do
      step = %{talk() | target_type: :creature_with_guid, target_param1: 999, target_self?: true}
      assert {^source, []} = deliver(actors, source, [step], target)
    end

    test "an absent provided target stays absent despite an active victim", %{actors: actors, guids: [source | _]} do
      assert {^source, [%Effects.MonsterTalk{target_guid: nil}]} = deliver(actors, source, [talk()], nil)
    end

    test "failed target resolution or conditions cannot terminate a script", %{
      actors: actors,
      guids: [source, target | _]
    } do
      missing = %ScriptStep{command: :terminate_script, target_type: :creature_with_guid}
      failing = %ScriptStep{command: :terminate_script, condition: %Condition{type: :source_entry, value1: 999}}

      for step <- [missing, failing] do
        assert {^source, [%Effects.MonsterTalk{}]} = deliver(actors, source, [step, talk()], target)
      end
    end

    test "both swaps can select a buddy when the initial target is absent", %{
      actors: actors,
      guids: [source, _, buddy | _]
    } do
      step = %{
        talk()
        | target_type: :creature_with_guid,
          buddy_guid: buddy,
          swap_initial?: true,
          swap_final?: true
      }

      for absent <- [nil, 0] do
        assert {^buddy, [%Effects.MonsterTalk{target_guid: 0}]} = deliver(actors, source, [step], absent)

        assert {^buddy, [%Effects.MonsterTalk{target_guid: ^buddy}]} =
                 deliver(actors, source, [%{step | target_self?: true}], absent)
      end

      for selector <- [:victim, :owner_or_self, :nearest_player] do
        assert {^source, []} = deliver(actors, source, [%{step | target_type: selector}], nil)
      end
    end

    test "game objects can own an initially swapped command", %{actors: actors, guids: [source | _]} do
      guid = Guid.from_low_guid(:game_object, 123, 5)
      object = %GameObject{object: %Object{guid: guid}, internal: %Internal{world: WorldRef.open(999)}}
      actors = Map.put(actors, guid, object)
      step = %ScriptStep{command: :play_custom_animation, datalong: 2, swap_initial?: true}

      assert {^guid, [%Effects.GameObjectCustomAnimation{animation: 2}]} = deliver(actors, source, [step], guid)
    end

    test "delayed swaps retain the original pair until the delay elapses", %{
      actors: actors,
      guids: [source, target | _]
    } do
      step = %{talk() | delay_ms: 1_000, swap_initial?: true}
      {scheduled, _} = Script.run(actors[source], Blackboard.new(), [step], target, 0)
      assert [%Effects.ScriptSteps{steps: [due], target_guid: ^target, duration_ms: 1_000}] = scheduled.internal.events
      assert due.swap_initial?
      assert due.delay_ms == 0
      assert {^target, [%Effects.MonsterTalk{target_guid: ^source}]} = deliver(actors, source, [due], target)
    end
  end

  defp deliver(actors, owner, steps, target, remaining \\ 3) do
    assert remaining >= 0
    {updated, _} = Script.run(actors[owner], Blackboard.new(), steps, target, Context.new(0))

    case updated.internal.events do
      [%Effects.ForwardScriptSteps{target_guid: next, steps: forwarded, source_guid: provided}] ->
        assert Enum.all?(forwarded, &(&1.delay_ms == 0))
        deliver(actors, next, forwarded, provided, remaining - 1)

      effects ->
        {owner, effects}
    end
  end

  defp talk do
    %ScriptStep{command: :talk, texts: [%{text: "Hello!", chat_type: :say, language: 0, emote_id: 0}]}
  end

  defp actors(_context) do
    guids = [Guid.from_low_guid(:mob, 1, 1), 2, Guid.from_low_guid(:mob, 3, 3), Guid.from_low_guid(:mob, 4, 4)]
    [source, target, source_victim, target_victim] = guids

    actors =
      Map.new(guids, fn guid ->
        target_guid = if guid == source, do: source_victim, else: target_victim

        mob = %Mob{
          object: %Object{guid: guid, entry: Guid.entry(guid)},
          unit: %Unit{health: 100, max_health: 100, level: 10, target: target_guid, auras: []},
          movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
          internal: %Internal{world: WorldRef.open(999), creature: %Creature{}, spellbook: %{}}
        }

        {guid, mob}
      end)

    character = struct!(Character, actors[target] |> Map.from_struct() |> Map.put(:player, %Player{}))
    {:ok, actors: Map.put(actors, target, character), guids: guids}
  end
end
