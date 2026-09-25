defmodule ThistleTea.Game.Entity.Server.ScriptDelivery do
  @moduledoc """
  Delivers one suspended script command without blocking either entity owner.
  Its short-lived worker monitors the caller and each selected receiver; every
  hop shares a deadline and reports one result to the original run receipt.
  """

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.AI.Script.Request
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Time

  @timeout_ms 5_000

  def start(%Context{owner_pid: owner}, receipt, %Effects.ForwardScriptSteps{} = effect) do
    Task.start(fn -> deliver(owner, receipt, effect) end)
    :ok
  end

  def start(nil, _receipt, _effect), do: :ok

  def forward(%Request{} = request, %Effects.ForwardScriptSteps{} = effect) do
    send(request.reply_to, {:script_forward, request.id, effect})
    :ok
  end

  def reply(%Request{} = request, status) when status in [:continue, :terminated, :failed] do
    send(request.reply_to, {:script_command_result, request.id, status})
    :ok
  end

  defp deliver(owner, {run_id, receipt, world}, effect) do
    caller_monitor = Process.monitor(owner)

    request = %Request{
      id: make_ref(),
      world: world,
      step: hd(effect.steps),
      target_guid: effect.source_guid,
      reply_to: self(),
      deadline: Time.now() + @timeout_ms
    }

    status = route(effect, request, caller_monitor)
    if status != :caller_down, do: send(owner, {:script_resume, run_id, receipt, world, status})
  rescue
    _error -> send(owner, {:script_resume, run_id, receipt, world, :failed})
  end

  defp route(effect, request, caller_monitor) do
    case Entity.pid(effect.target_guid) do
      pid when is_pid(pid) ->
        monitor = Process.monitor(pid)
        request = %{request | step: hd(effect.steps), target_guid: effect.source_guid}
        send(pid, {:script_command, request})
        await(request, caller_monitor, monitor)

      _missing ->
        :failed
    end
  end

  defp await(%Request{id: id} = request, caller_monitor, receiver_monitor) do
    receive do
      {:script_command_result, ^id, status} when status in [:continue, :terminated, :failed] ->
        status

      {:script_forward, ^id, %Effects.ForwardScriptSteps{} = effect} ->
        Process.demonitor(receiver_monitor, [:flush])
        route(effect, request, caller_monitor)

      {:DOWN, ^caller_monitor, :process, _pid, _reason} ->
        :caller_down

      {:DOWN, ^receiver_monitor, :process, _pid, _reason} ->
        :failed
    after
      max(request.deadline - Time.now(), 0) -> :failed
    end
  end
end
