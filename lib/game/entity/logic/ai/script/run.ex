defmodule ThistleTea.Game.Entity.Logic.AI.Script.Run do
  @moduledoc """
  Retains script continuations on their original owner. Due times stay relative
  to the original start, and each wait has a distinct receipt. Only the current
  receipt can advance a run; no entity or blackboard snapshot is retained.
  """

  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard.EventAI.Actions
  alias ThistleTea.Game.Entity.Logic.AI.Script
  alias ThistleTea.Game.Entity.Logic.Effects

  defstruct [
    :id,
    :world,
    :source_guid,
    :target_guid,
    :script_id,
    :started_at,
    :completion,
    :waiting,
    steps: [],
    receipt: 0
  ]

  def start(state, blackboard, steps, target_guid, context, mode, completion \\ nil) do
    steps = if mode == :direct, do: Enum.map(steps, &%{&1 | delay_ms: 0}), else: steps

    run = %__MODULE__{
      world: state.internal.world,
      source_guid: state.object.guid,
      target_guid: target_guid,
      script_id:
        case steps do
          [step | _] -> step.script_id
          [] -> 0
        end,
      started_at: context.now,
      steps: Enum.sort_by(steps, & &1.delay_ms),
      completion: completion
    }

    advance(state, blackboard, run, context)
  end

  def pending(state, id), do: Map.get(state.internal.scripts.runs, id)

  def resume(state, blackboard, id, receipt, world, result, context) when result in [:continue, :terminated, :failed] do
    case pending(state, id) do
      %__MODULE__{receipt: ^receipt, world: ^world} = run ->
        cond do
          not active?(state, blackboard, run) -> {remove(state, id), blackboard}
          result == :terminated -> finish(state, blackboard, run, :terminated)
          result == :failed and run.waiting == :abort_on_failure -> finish(state, blackboard, run, :terminated)
          true -> advance(state, blackboard, %{run | waiting: nil}, context)
        end
        |> without_status()

      _stale ->
        {state, blackboard}
    end
  end

  def clear(state), do: %{state | internal: %{state.internal | scripts: %{state.internal.scripts | runs: %{}}}}

  def active?(state, blackboard, %__MODULE__{world: world} = run) do
    state.internal.world == world and completion_active?(blackboard, run)
  end

  defp completion_active?(blackboard, %__MODULE__{id: id, completion: {:event_ai, index, token}}) do
    case Map.get(blackboard.event_ai.pending, index) do
      %Actions{token: ^token, runs: runs} -> MapSet.member?(runs, id)
      _stale -> false
    end
  end

  defp completion_active?(_blackboard, %__MODULE__{}), do: true

  defp advance(state, blackboard, %__MODULE__{steps: []} = run, _context), do: finish(state, blackboard, run, :continue)

  defp advance(state, blackboard, %__MODULE__{steps: [step | remaining]} = run, context) do
    delay = run.started_at + step.delay_ms - context.now

    if delay > 0 do
      {state, run} = retain(state, %{run | waiting: :timer})
      steps = Enum.map(run.steps, &%{&1 | delay_ms: &1.delay_ms - step.delay_ms})
      effect = %{Effects.script_steps(steps, run.target_guid, delay) | run_id: run.id, receipt: run.receipt}
      {Effects.enqueue(state, effect), blackboard, {:pending, run.id}}
    else
      execute(state, blackboard, %{run | steps: remaining}, step, context)
    end
  end

  defp execute(state, blackboard, run, step, context) do
    case Script.execute_step(state, blackboard, step, run.target_guid, context) do
      {state, blackboard, :continue} ->
        advance(state, blackboard, run, context)

      {state, blackboard, :terminated} ->
        finish(state, blackboard, %{run | script_id: step.script_id}, :terminated)

      {state, blackboard, {:await, effect}} ->
        waiting = if step.abort_on_failure?, do: :abort_on_failure, else: :continue_on_failure
        {state, run} = retain(state, %{run | waiting: waiting})
        effect = %{effect | reply: {run.id, run.receipt, run.world}}
        {Effects.enqueue(state, effect), blackboard, {:pending, run.id}}
    end
  end

  defp retain(state, %__MODULE__{id: nil} = run) do
    scripts = state.internal.scripts
    id = scripts.sequence + 1
    state = %{state | internal: %{state.internal | scripts: %{scripts | sequence: id}}}
    retain(state, %{run | id: id})
  end

  defp retain(state, %__MODULE__{} = run) do
    run = %{run | receipt: run.receipt + 1}
    scripts = state.internal.scripts
    state = %{state | internal: %{state.internal | scripts: %{scripts | runs: Map.put(scripts.runs, run.id, run)}}}
    {state, run}
  end

  defp finish(state, blackboard, run, :terminated) do
    matching =
      state.internal.scripts.runs
      |> Map.values()
      |> Enum.filter(&same_script?(&1, run))

    state = Enum.reduce(matching, state, fn other, state -> complete(state, other, :terminated) end)
    state = if Enum.any?(matching, &(&1.id == run.id)), do: state, else: complete(state, run, :terminated)
    {state, blackboard, :terminated}
  end

  defp finish(state, blackboard, run, :continue), do: {complete(state, run, :continue), blackboard, :continue}

  defp complete(state, %__MODULE__{} = run, status) do
    state = remove(state, run.id)

    if run.id && run.completion do
      Effects.enqueue(state, %Effects.ScriptCompleted{run_id: run.id, completion: run.completion, status: status})
    else
      state
    end
  end

  defp same_script?(%__MODULE__{id: id}, %__MODULE__{id: id}) when not is_nil(id), do: true

  defp same_script?(left, right) do
    right.script_id > 0 and
      {left.world, left.source_guid, left.target_guid, left.script_id} ==
        {right.world, right.source_guid, right.target_guid, right.script_id}
  end

  defp remove(state, id) do
    scripts = state.internal.scripts
    %{state | internal: %{state.internal | scripts: %{scripts | runs: Map.delete(scripts.runs, id)}}}
  end

  defp without_status({state, blackboard, _status}), do: {state, blackboard}
  defp without_status({state, blackboard}), do: {state, blackboard}
end
