defmodule ThistleTea.Game.World.Entity.Player.Tickets do
  @moduledoc """
  The player's side of the help frame: shows their ticket and the queue's
  ages, files, edits, and abandons it, and tells the player when it has been
  answered.
  """

  alias ThistleTea.Game.Core.GmTicket
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Login
  alias ThistleTea.Game.World.Outbound
  alias ThistleTea.Game.World.System.GmTickets
  alias ThistleTea.Game.World.System.GmTickets.View

  @create_success 2
  @create_error 3
  @update_success 4
  @update_error 5
  @deleted 9
  @read_only "This ticket has already been completed. Please open a new one."
  @answered "Your ticket has been edited with a response."

  def show(%{ready: true, guid: guid} = state) do
    Login.query_time(state)
    view = GmTickets.view(guid)
    Outbound.send_packet(packet(view, Time.now()), guid)
    if match?(%View{ticket: %GmTicket{completed?: true}}, view), do: tell(guid, @answered)
    state
  end

  def show(state), do: state

  def create(%{ready: true, guid: guid, character: character} = state, type, map_id, position, message) do
    response =
      with true <- GmTicket.type?(type),
           {:ok, _ticket} <- GmTickets.create(guid, character.internal.name, type, message, map_id, position) do
        @create_success
      else
        _refused -> @create_error
      end

    Outbound.send_packet(%Message.SmsgGmticketCreate{response: response}, guid)
    state
  end

  def create(state, _type, _map_id, _position, _message), do: state

  def update_text(%{ready: true, guid: guid} = state, type, message) do
    response =
      case GmTickets.update_text(guid, type, message) do
        {:ok, _ticket} ->
          @update_success

        {:completed, _ticket} ->
          tell(guid, @read_only)
          Outbound.send_packet(packet(GmTickets.view(guid), Time.now()), guid)
          @update_error

        :error ->
          @update_error
      end

    Outbound.send_packet(%Message.SmsgGmticketUpdatetext{response: response}, guid)
    state
  end

  def update_text(state, _type, _message), do: state

  def abandon(%{ready: true, guid: guid} = state) do
    if GmTickets.abandon(guid) == :ok do
      Outbound.send_packet(%Message.SmsgGmticketDeleteticket{response: @deleted}, guid)
      Outbound.send_packet(%Message.SmsgGmticketGetticket{}, guid)
    end

    state
  end

  def abandon(state), do: state

  def system_status(%{ready: true, guid: guid} = state) do
    Outbound.send_packet(%Message.SmsgGmticketSystemstatus{}, guid)
    state
  end

  def system_status(state), do: state

  def answered(%GmTicket{player_guid: guid}) do
    Outbound.send_packet(packet(GmTickets.view(guid), Time.now()), guid)
    tell(guid, @answered)
  end

  def packet(nil, _now), do: %Message.SmsgGmticketGetticket{}

  def packet(%View{ticket: %GmTicket{} = ticket} = view, now) do
    %Message.SmsgGmticketGetticket{
      message: GmTicket.display_message(ticket),
      type: ticket.type,
      last_modified_age: GmTicket.age_days(ticket.modified_at, now),
      oldest_ticket_age: GmTicket.age_days(view.oldest_at, now),
      estimated_wait_time: GmTicket.age_days(view.last_change, now),
      opened_by_gm: if(ticket.viewed?, do: 1, else: 0)
    }
  end

  defp tell(guid, text), do: Outbound.send_packet(Message.SmsgMessagechat.system(text, guid), guid)
end
