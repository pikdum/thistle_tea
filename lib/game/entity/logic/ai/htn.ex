defmodule ThistleTea.Game.Entity.Logic.AI.HTN do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  defstruct tasks: %{}, steps: %{}, root: nil

  defmodule Method do
    defstruct [:guard, :subtasks]
  end

  def new do
    %__MODULE__{}
  end

  def root(%__MODULE__{} = htn, root) when is_atom(root) do
    %{htn | root: root}
  end

  def task(%__MODULE__{} = htn, name, methods) when is_atom(name) and is_list(methods) do
    %{htn | tasks: Map.put(htn.tasks, name, methods)}
  end

  def method(guard, subtasks) when is_function(guard, 1) and is_list(subtasks) do
    %Method{guard: guard, subtasks: subtasks}
  end

  def step(%__MODULE__{} = htn, name, fun) when is_atom(name) and is_function(fun, 2) do
    %{htn | steps: Map.put(htn.steps, name, fun)}
  end

  def start(state, %__MODULE__{root: root} = htn) when is_atom(root) do
    queue = plan(htn, root, state)
    state = put_htn_state(state, queue, ctx(state), root)
    {state, 0}
  end

  def step(state, %__MODULE__{root: root} = htn) when is_atom(root) do
    {queue, htn_ctx} = htn_state(state)
    queue = if queue == [], do: plan(htn, root, state), else: queue

    case queue do
      [] ->
        {state, default_delay()}

      [step | rest] ->
        {state, delay, htn_ctx, rest} = apply_step(state, htn, step, htn_ctx, rest)
        state = put_htn_state(state, rest, htn_ctx, root)
        {state, delay}
    end
  end

  defp apply_step(state, %__MODULE__{steps: steps}, step, htn_ctx, rest) do
    case Map.get(steps, step) do
      nil ->
        {state, default_delay(), htn_ctx, rest}

      fun ->
        case fun.(state, htn_ctx) do
          {:ok, state, htn_ctx, delay} ->
            {state, delay, htn_ctx, rest}

          {:replan, state, htn_ctx, delay} ->
            {state, delay, htn_ctx, []}
        end
    end
  end

  defp plan(%__MODULE__{steps: steps, tasks: tasks}, name, state) do
    cond do
      Map.has_key?(steps, name) ->
        [name]

      Map.has_key?(tasks, name) ->
        tasks
        |> Map.get(name, [])
        |> Enum.find(fn %Method{guard: guard} -> guard.(state) end)
        |> case do
          nil -> []
          %Method{subtasks: subtasks} -> expand_subtasks(%__MODULE__{steps: steps, tasks: tasks}, subtasks, state)
        end

      true ->
        []
    end
  end

  defp expand_subtasks(htn, subtasks, state) do
    Enum.flat_map(subtasks, fn subtask -> plan(htn, subtask, state) end)
  end

  defp ctx(state) do
    htn_ctx = htn_ctx(state)
    if is_map(htn_ctx), do: htn_ctx, else: %{}
  end

  defp htn_state(state) do
    htn_state = htn_map(state)
    {Map.get(htn_state, :queue, []), Map.get(htn_state, :ctx, %{})}
  end

  defp htn_ctx(state) do
    htn_map(state)
    |> Map.get(:ctx, %{})
  end

  defp htn_map(%{internal: %Internal{ai_state: ai_state}}) when is_map(ai_state) do
    Map.get(ai_state, :htn, %{})
  end

  defp htn_map(_state) do
    %{}
  end

  defp put_htn_state(%{internal: %Internal{} = internal} = state, queue, htn_ctx, root) do
    ai_state = if is_map(internal.ai_state), do: internal.ai_state, else: %{}
    htn_state = %{queue: queue, ctx: htn_ctx, root: root}
    %{state | internal: %{internal | ai_state: Map.put(ai_state, :htn, htn_state)}}
  end

  defp put_htn_state(state, _queue, _htn_ctx, _root) do
    state
  end

  defp default_delay do
    1_000
  end
end
