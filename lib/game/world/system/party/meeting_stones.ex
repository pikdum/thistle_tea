defmodule ThistleTea.Game.World.System.Party.MeetingStones do
  @moduledoc "Meeting Stone runtime snapshots and queue packet projection, executed by the party owner."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.MeetingStone
  alias ThistleTea.Game.Core.MeetingStone.Applicant
  alias ThistleTea.Game.Core.Party
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Outbound

  def request(queue, party, :join, guid, area, now) do
    case MeetingStone.join(queue, party, applicant(guid), area, now) do
      {:ok, queue, events} -> {queue, events}
      {:error, :unavailable} -> {queue, []}
      {:error, reason} -> {queue, [{:failed, [guid], reason}]}
    end
  end

  def request(queue, party, :leave, guid, _area, _now), do: MeetingStone.leave(queue, party, guid)
  def request(queue, party, :info, guid, _area, _now), do: {queue, [MeetingStone.status(queue, party, guid)]}

  def refresh(queue, party, now) do
    group_members =
      queue.groups
      |> Map.keys()
      |> Enum.flat_map(fn id ->
        case party.groups[id] do
          %Party.Group{} = group -> Enum.map(group.members, & &1.guid)
          _ -> []
        end
      end)

    players = Map.new(MeetingStone.candidates(queue) ++ group_members, &{&1, applicant(&1)})
    MeetingStone.refresh(queue, party, players, now)
  end

  def applicant(guid) do
    case CharacterStore.get(guid) do
      %Character{} = character ->
        %Applicant{
          guid: guid,
          name: character.internal.name,
          class: character.unit.class,
          team: team(character.unit.race),
          online?: Entity.online?(guid) and World.position(guid) != nil
        }

      _ ->
        %Applicant{guid: guid}
    end
  end

  def deliver({:status, recipients, area, status}),
    do: send_to(recipients, %Message.SmsgMeetingstoneSetqueue{area: area, status: status})

  def deliver({:failed, recipients, reason}),
    do: send_to(recipients, %Message.SmsgMeetingstoneJoinfailed{reason: failure(reason)})

  def deliver({:member, recipients, guid}), do: send_to(recipients, %Message.SmsgMeetingstoneMemberAdded{guid: guid})

  def deliver({:complete, recipients}), do: send_to(recipients, %Message.SmsgMeetingstoneComplete{})
  def deliver({:progress, recipients}), do: send_to(recipients, %Message.SmsgMeetingstoneInProgress{})

  defp send_to(recipients, packet), do: Enum.each(recipients, &Outbound.send_packet(packet, &1))
  defp failure(:not_leader), do: 1
  defp failure(:full_group), do: 2
  defp failure(:raid_group), do: 3
  defp team(race) when race in [1, 3, 4, 7], do: :alliance
  defp team(race) when race in [2, 5, 6, 8], do: :horde
  defp team(_race), do: nil
end
