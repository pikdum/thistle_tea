defmodule ThistleTea.Game.Player.PetActions do
  @moduledoc "Validates and dispatches commands to owned creatures and possessed players."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec

  @act_command 0x07
  @act_reaction 0x06

  def handle(%Message.CmsgPetAction{pet_guid: pet_guid} = message, %{character: %Character{} = character} = state) do
    if Character.controls?(character, pet_guid) and valid_action?(character, message) do
      case Entity.pid(pet_guid) do
        pid when is_pid(pid) -> dispatch(pid, character.object.guid, message)
        _ -> :ok
      end
    end

    state
  end

  def handle(%Message.CmsgPetAction{}, state), do: state

  def cast(%{character: %Character{} = character} = state, %Message.CmsgPetCastSpell{} = message) do
    if Character.controls?(character, message.pet_guid) and Guid.entity_type(message.pet_guid) == :mob do
      targets = TargetCodec.parse(message.spell_cast_targets, message.pet_guid)
      dispatch_cast(message.pet_guid, character.object.guid, message.spell_id, targets)
    end

    state
  end

  def cast(state, %Message.CmsgPetCastSpell{}), do: state

  def controls(%{character: %Character{} = character} = state, guid, request) do
    with true <- Character.controls?(character, guid) and Guid.entity_type(guid) == :mob,
         {:ok, _spells, control} <- Entity.call(guid, {:pet_controls, character.object.guid, request}) do
      %{state | character: Companion.remember_controls(character, guid, control)}
    else
      _ -> state
    end
  end

  def controls(state, _guid, _request), do: state

  def stop_attack(%{character: %Character{} = character} = state, guid) do
    with true <- Character.controls?(character, guid),
         pid when is_pid(pid) <- Entity.pid(guid) do
      request =
        if Guid.entity_type(guid) == :player,
          do: {:controlled_command, character.object.guid, :stop_attack, 0},
          else: {:pet_stop_attack, character.object.guid}

      send(pid, request)
    end

    state
  end

  def stop_attack(state, _guid), do: state

  def cancel_aura(%{character: %Character{} = character} = state, guid, spell) do
    if Character.controls?(character, guid) and Guid.entity_type(guid) == :mob and
         is_nil(Companion.possession_guid(character)) and self_mover?(state, character.object.guid) do
      case Entity.pid(guid) do
        pid when is_pid(pid) -> send(pid, {:pet_cancel_aura, character.object.guid, spell})
        _ -> :ok
      end
    end

    state
  end

  def cancel_aura(state, _guid, _spell), do: state

  defp self_mover?(%{active_mover_guid: mover}, guid), do: mover in [nil, guid]
  defp self_mover?(_state, _guid), do: true

  defp dispatch(pid, controller, %Message.CmsgPetAction{pet_guid: guid} = message) do
    if Guid.entity_type(guid) == :player do
      dispatch_player(pid, controller, message)
    else
      dispatch_creature(pid, controller, message)
    end
  end

  defp dispatch_player(pid, controller, %Message.CmsgPetAction{
         action_type: @act_command,
         action: action,
         target_guid: target
       }) do
    send(pid, {:controlled_command, controller, command(action), target})
  end

  defp dispatch_player(pid, controller, %Message.CmsgPetAction{action_type: @act_reaction, action: action}) do
    send(pid, {:controlled_command, controller, reaction(action), 0})
  end

  defp dispatch_player(_pid, _controller, _message), do: :ok

  defp dispatch_creature(pid, _controller, %Message.CmsgPetAction{
         action_type: @act_command,
         action: action,
         target_guid: target_guid
       }) do
    send(pid, {:pet_command, command(action), target_guid})
  end

  defp dispatch_creature(pid, _controller, %Message.CmsgPetAction{action_type: @act_reaction, action: action}) do
    send(pid, {:pet_reaction, reaction(action)})
  end

  defp dispatch_creature(pid, controller, %Message.CmsgPetAction{action: spell_id, target_guid: target_guid})
       when spell_id > 0 do
    targets = if is_integer(target_guid) and target_guid > 0, do: Target.unit(target_guid), else: Target.none()
    send(pid, {:pet_cast, controller, spell_id, targets})
  end

  defp dispatch_creature(_pid, _controller, _message), do: :ok

  defp dispatch_cast(guid, controller, spell_id, targets) do
    case Entity.pid(guid) do
      pid when is_pid(pid) -> send(pid, {:pet_cast, controller, spell_id, targets})
      _ -> :ok
    end
  end

  defp valid_action?(character, %Message.CmsgPetAction{action_type: @act_command, action: 2, target_guid: target_guid}) do
    cond do
      not (is_integer(target_guid) and target_guid > 0) ->
        reject_attack(:nothing_to_attack)

      not Hostility.valid_attack_target?(character, target_guid) ->
        reject_attack(:cant_attack_target)

      true ->
        true
    end
  end

  defp valid_action?(_character, _message), do: true

  defp reject_attack(feedback) do
    Network.send_packet(Message.SmsgPetActionFeedback.new(feedback))
    false
  end

  defp command(0), do: :stay
  defp command(1), do: :follow
  defp command(2), do: :attack
  defp command(3), do: :dismiss
  defp command(_), do: :unknown

  defp reaction(0), do: :passive
  defp reaction(1), do: :defensive
  defp reaction(2), do: :aggressive
  defp reaction(_), do: :defensive
end
