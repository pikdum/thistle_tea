defmodule ThistleTea.Game.Entity.Logic.AI.BT do
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard

  defstruct type: nil, children: [], fun: nil

  def selector(children) when is_list(children) do
    %__MODULE__{type: :selector, children: children}
  end

  def sequence(children) when is_list(children) do
    %__MODULE__{type: :sequence, children: children}
  end

  def condition(fun) when is_function(fun, 2) do
    %__MODULE__{type: :condition, fun: fun}
  end

  def action(fun) when is_function(fun, 2) do
    %__MODULE__{type: :action, fun: fun}
  end

  def tick(tree, state, now \\ current_time_ms()) do
    blackboard = state |> blackboard() |> Blackboard.with_now(now)
    {status, state, blackboard} = run(tree, state, blackboard)
    {status, put_blackboard(state, blackboard)}
  end

  def init(state, behavior_tree, blackboard \\ Blackboard.new()) do
    state
    |> put_behavior_tree(behavior_tree)
    |> put_blackboard(blackboard)
  end

  def interrupt(state) do
    put_blackboard(state, Blackboard.new())
  end

  defp run(%__MODULE__{type: :condition, fun: fun}, state, blackboard) do
    if fun.(state, blackboard), do: {:success, state, blackboard}, else: {:failure, state, blackboard}
  end

  defp run(%__MODULE__{type: :action, fun: fun}, state, blackboard) do
    fun.(state, blackboard)
  end

  defp run(%__MODULE__{type: :selector, children: children}, state, blackboard) do
    Enum.reduce_while(children, {:failure, state, blackboard}, fn child, {_status, s, b} ->
      case run(child, s, b) do
        {:failure, s, b} -> {:cont, {:failure, s, b}}
        {:success, s, b} -> {:halt, {:success, s, b}}
        {:running, s, b} -> {:halt, {:running, s, b}}
        {{:running, _delay} = status, s, b} -> {:halt, {status, s, b}}
      end
    end)
  end

  defp run(%__MODULE__{type: :sequence, children: children}, state, blackboard) do
    Enum.reduce_while(children, {:success, state, blackboard}, fn child, {_status, s, b} ->
      case run(child, s, b) do
        {:success, s, b} -> {:cont, {:success, s, b}}
        {:failure, s, b} -> {:halt, {:failure, s, b}}
        {:running, s, b} -> {:halt, {:running, s, b}}
        {{:running, _delay} = status, s, b} -> {:halt, {status, s, b}}
      end
    end)
  end

  defp blackboard(%{internal: %Internal{blackboard: blackboard}}) do
    Blackboard.from_any(blackboard)
  end

  defp blackboard(_state) do
    Blackboard.new()
  end

  defp put_behavior_tree(%{internal: %Internal{} = internal} = state, behavior_tree) do
    %{state | internal: %{internal | behavior_tree: behavior_tree}}
  end

  defp put_behavior_tree(state, _behavior_tree), do: state

  defp put_blackboard(%{internal: %Internal{} = internal} = state, %Blackboard{} = blackboard) do
    %{state | internal: %{internal | blackboard: blackboard}}
  end

  defp put_blackboard(state, _blackboard), do: state

  defp current_time_ms do
    System.monotonic_time(:millisecond)
  end
end
