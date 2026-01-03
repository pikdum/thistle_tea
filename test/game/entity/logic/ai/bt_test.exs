defmodule ThistleTea.Game.Entity.Logic.AI.BTTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard

  defp build_state(blackboard \\ nil) do
    %{internal: %Internal{blackboard: blackboard}}
  end

  defp always_false(_state, _blackboard), do: false

  defp set_target(state, %Blackboard{} = blackboard) do
    {:success, state, %{blackboard | target: :selected}}
  end

  defp keep_running(state, %Blackboard{} = blackboard) do
    {:running, state, %{blackboard | target: :running}}
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

    {:success, state} = BT.tick(tree, state, 123)

    assert state.internal.blackboard.target == :selected
    assert state.internal.blackboard.now == 123
  end

  test "sequence stops on running child" do
    tree = BT.sequence([BT.action(&keep_running/2), BT.action(&set_target/2)])

    state = build_state()

    {:running, state} = BT.tick(tree, state, 456)

    assert state.internal.blackboard.target == :running
  end
end
