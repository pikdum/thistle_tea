defmodule ThistleTea.Game.Entity.Server.Player.PossessionOwner.Monitor do
  @moduledoc false
  @enforce_keys [:caster_guid, :spell_id, :pid, :token]
  defstruct [:caster_guid, :spell_id, :pid, :token]
end

defmodule ThistleTea.Game.Entity.Server.Player.PossessionOwner do
  @moduledoc "Monitors an incoming controller and serializes player possession commands and teardown."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Possession
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.PlayerCharm
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.PlayerPossession
  alias ThistleTea.Game.Entity.Server.Player.PossessionOwner.Monitor
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Player.Attacking
  alias ThistleTea.Game.Player.Looting
  alias ThistleTea.Game.Player.Movement
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.System.Trade

  def reconcile(%State{character: %Character{internal: %{possession: nil}}} = state), do: clear_monitor(state)

  def reconcile(%State{character: %Character{internal: %{possession: %Possession{} = possession}}} = state) do
    case state.possession_monitor do
      %Monitor{caster_guid: caster, spell_id: spell}
      when caster == possession.caster_guid and spell == possession.spell_id ->
        state

      _previous ->
        state = clear_monitor(state)

        case Entity.pid(possession.caster_guid) do
          pid when is_pid(pid) ->
            monitor = %Monitor{
              caster_guid: possession.caster_guid,
              spell_id: possession.spell_id,
              pid: pid,
              token: Process.monitor(pid)
            }

            Trade.cancel(state.guid)
            state = Looting.release(state)
            %{state | possession_monitor: monitor}

          _missing ->
            release(state)
        end
    end
  end

  def reconcile(state), do: state

  def release(%State{character: %Character{} = character} = state) do
    {character, events} = Aura.remove_aura_types(character, [:mod_possess, :mod_charm, :aoe_charm], Time.now())
    clear_monitor(%{state | character: EventSink.emit(character, events)})
  end

  def release(%State{} = state), do: clear_monitor(state)

  def release(%State{character: %Character{internal: %{possession: %Possession{} = possession}}} = state, caster, spell)
      when possession.caster_guid == caster and possession.spell_id == spell, do: release(state)

  def release(%State{} = state, _caster, _spell), do: state

  def move(%State{ready: true, character: %Character{} = character} = state, caster, payload, opcode) do
    if authorized?(character, caster) and PlayerPossession.manually_controlled?(character),
      do: Movement.handle_controlled(state, caster, payload, opcode),
      else: state
  end

  def move(%State{} = state, _caster, _payload, _opcode), do: state

  def command(%State{ready: true, character: %Character{} = character} = state, caster, command, target) do
    if authorized?(character, caster), do: apply_command(state, command, target), else: state
  end

  def command(%State{} = state, _caster, _command, _target), do: state

  defp authorized?(character, caster) do
    world = character.internal.world

    PlayerPossession.controlled_by?(character, caster) and not Core.dead?(character) and
      match?({^world, _, _, _}, World.position(caster))
  end

  defp apply_command(state, :dismiss, _target), do: release(state)

  defp apply_command(state, :stop_attack, _target) do
    {character, events} = PlayerCombat.stop_melee_attack(state.character)
    character = character |> EventSink.emit(events) |> Core.mark_broadcast_update()
    %{state | character: character}
  end

  defp apply_command(
         %State{character: %Character{internal: %{possession: %Possession{kind: :charm}}}} = state,
         command,
         target
       ) do
    character = PlayerCharm.command(state.character, command, target, Time.now())
    %{state | character: EventSink.emit_pending(character)}
  end

  defp apply_command(state, :attack, target) do
    Attacking.start(state, target)
  end

  defp apply_command(state, command, _target) when command in [:stay, :follow, :passive] do
    {character, events} = PlayerCombat.stop_attack(state.character)
    %{state | character: EventSink.emit(character, events)}
  end

  defp apply_command(state, _command, _target), do: state

  defp clear_monitor(%State{possession_monitor: %Monitor{token: token}} = state) do
    Process.demonitor(token, [:flush])
    %{state | possession_monitor: nil}
  end

  defp clear_monitor(%State{} = state), do: state
end
