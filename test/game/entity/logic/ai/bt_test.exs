defmodule ThistleTea.Game.Entity.Logic.AI.BTTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context

  defp build_state(blackboard \\ nil) do
    %{internal: %Internal{blackboard: blackboard}}
  end

  defp always_false(_state, _blackboard), do: false

  defp set_target(state, %Blackboard{} = blackboard) do
    navigation = %{blackboard.navigation | target: :selected}
    {:success, state, %{blackboard | navigation: navigation}}
  end

  defp keep_running(state, %Blackboard{} = blackboard) do
    navigation = %{blackboard.navigation | target: :running}
    {:running, state, %{blackboard | navigation: navigation}}
  end

  defp keep_running_with_reason(state, %Blackboard{} = blackboard) do
    navigation = %{blackboard.navigation | target: :running_with_reason}
    {BT.running(250, :test), state, %{blackboard | navigation: navigation}}
  end

  test "selector falls through on failure and updates blackboard" do
    tree =
      BT.selector([
        BT.sequence([
          BT.condition(&always_false/2),
          BT.action(&set_target/2)
        ]),
        BT.action(&set_target/2)
      ])

    state = build_state()

    {:success, state} = BT.tick(tree, state, Context.new(1_000))

    assert state.internal.blackboard.navigation.target == :selected
  end

  test "sequence stops on running child" do
    tree = BT.sequence([BT.action(&keep_running/2), BT.action(&set_target/2)])

    state = build_state()

    {:running, state} = BT.tick(tree, state, Context.new(1_000))

    assert state.internal.blackboard.navigation.target == :running
  end

  test "sequence preserves reason-tagged running status" do
    tree = BT.sequence([BT.action(&keep_running_with_reason/2), BT.action(&set_target/2)])

    state = build_state()

    {{:running, 250, :test}, state} = BT.tick(tree, state, Context.new(1_000))

    assert state.internal.blackboard.navigation.target == :running_with_reason
  end

  test "passes the explicit environment to context-aware nodes" do
    tree =
      BT.action(fn state, blackboard, %Context{now: now} ->
        {:success, Map.put(state, :now, now), blackboard}
      end)

    {:success, state} = BT.tick(tree, build_state(), Context.new(42))

    assert state.now == 42
  end
end
