defmodule ThistleTea.Game.World.Entity.ScriptExecution do
  @moduledoc """
  Builds fresh observations for script receipts on an entity owner. Resuming
  runs and remotely selected commands share preparation and world checks.
  """

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Request, as: ObservationRequest
  alias ThistleTea.Game.Core.AI.Script
  alias ThistleTea.Game.Core.AI.Script.Request
  alias ThistleTea.Game.Core.AI.Script.Run
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Movement
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.World.Entity.AIEnvironment
  alias ThistleTea.Game.World.Entity.Mob.Corpse
  alias ThistleTea.Game.World.Entity.NavigationResolver
  alias ThistleTea.Game.World.Entity.ScriptSpells

  require Logger

  def resume(entity, id, receipt, world, status) do
    case Run.pending(entity, id) do
      %Run{receipt: ^receipt, world: ^world} = run ->
        resume_run(entity, run, status)

      _stale ->
        entity
    end
  rescue
    error ->
      Logger.error("script continuation failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      resume_without_observation(entity, id, receipt, world, :terminated)
  end

  defp resume_run(entity, %Run{} = run, status) do
    blackboard = Blackboard.ensure(entity.internal.blackboard)

    cond do
      removed?(entity) ->
        Run.clear(entity)

      not Run.active?(entity, blackboard, run) ->
        resume_without_observation(entity, run.id, run.receipt, run.world, status)

      true ->
        execute(entity, run.steps, run.target_guid, fn entity, blackboard, context ->
          Run.resume(entity, blackboard, run.id, run.receipt, run.world, status, context)
        end)
    end
  end

  defp resume_without_observation(entity, id, receipt, world, status) do
    now = Time.now()
    blackboard = Blackboard.ensure(entity.internal.blackboard)
    {entity, blackboard} = Run.resume(entity, blackboard, id, receipt, world, status, Context.new(now))
    retain_blackboard(entity, blackboard, now)
  end

  def command(entity, %Request{} = request) do
    if available?(entity, request) do
      execute(entity, [request.step], request.target_guid, fn entity, blackboard, context ->
        execute_command(entity, blackboard, request, context)
      end)
    else
      Effects.enqueue(entity, %Effects.ScriptReply{request: request, status: :failed})
    end
  end

  defp execute_command(entity, blackboard, request, context) do
    if available?(entity, request) do
      case Script.execute_step(entity, blackboard, request.step, request.target_guid, context) do
        {entity, blackboard, {:await, effect}} ->
          {Effects.enqueue(entity, %{effect | reply: request}), blackboard}

        {entity, blackboard, status} ->
          {Effects.enqueue(entity, %Effects.ScriptReply{request: request, status: status}), blackboard}
      end
    else
      {Effects.enqueue(entity, %Effects.ScriptReply{request: request, status: :failed}), blackboard}
    end
  end

  defp available?(entity, %Request{} = request),
    do:
      entity.internal.world == request.world and not removed?(entity) and Time.now() <= request.deadline and
        Process.alive?(request.reply_to)

  defp removed?(%Mob{} = entity), do: Corpse.removed?(entity)
  defp removed?(_entity), do: false

  defp execute(entity, steps, target_guid, apply) do
    entity = prepare(entity, steps)
    now = Time.now()
    entity = Movement.sync_position(entity, now)

    request = ObservationRequest.for_script(steps, [target_guid])

    context = AIEnvironment.context(entity, now, request)
    {entity, blackboard} = apply.(entity, Blackboard.ensure(entity.internal.blackboard), context)
    retain_blackboard(entity, blackboard, now)
  end

  defp prepare(%Mob{} = entity, steps), do: ScriptSpells.prepare(entity, steps)
  defp prepare(entity, _steps), do: entity

  defp retain_blackboard(%Mob{} = entity, blackboard, now),
    do: NavigationResolver.resolve(%{entity | internal: %{entity.internal | blackboard: blackboard}}, now)

  defp retain_blackboard(entity, _blackboard, _now), do: entity
end
