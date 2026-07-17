defmodule ThistleTea.Game.Entity.Logic.Aura.ViewpointSync do
  @moduledoc """
  Derives camera ownership transitions from bind-sight auras without coupling
  aura logic to player processes or update packets.
  """

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Event

  def events(previous_holders, current_holders, target_guid)
      when is_list(previous_holders) and is_list(current_holders) and is_integer(target_guid) do
    previous = bind_sight_holder(previous_holders)
    current = bind_sight_holder(current_holders)

    if same_owner?(previous, current) do
      []
    else
      release_event(previous, target_guid) ++ grant_event(current, target_guid)
    end
  end

  def events(_previous_holders, _current_holders, _target_guid), do: []

  defp bind_sight_holder(holders), do: Enum.find(holders, &Holder.has_aura_type?(&1, :bind_sight))

  defp same_owner?(%Holder{caster_guid: owner_guid}, %Holder{caster_guid: owner_guid}), do: true
  defp same_owner?(nil, nil), do: true
  defp same_owner?(_previous, _current), do: false

  defp release_event(%Holder{caster_guid: owner_guid}, target_guid),
    do: [Event.viewpoint_released(owner_guid, target_guid)]

  defp release_event(nil, _target_guid), do: []

  defp grant_event(%Holder{caster_guid: owner_guid}, target_guid),
    do: [Event.viewpoint_granted(owner_guid, target_guid)]

  defp grant_event(nil, _target_guid), do: []
end
