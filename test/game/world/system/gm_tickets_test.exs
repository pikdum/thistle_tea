defmodule ThistleTea.Game.World.System.GmTicketsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GmTicket
  alias ThistleTea.Game.World.System.GmTickets
  alias ThistleTea.Game.World.System.GmTickets.View
  alias ThistleTea.Test.Unique

  setup do
    server = start_supervised!({GmTickets, name: :"gm_tickets_#{Unique.integer()}"})
    %{server: server}
  end

  describe "create/8" do
    test "keeps one open ticket per character until it is answered", %{server: server} do
      assert {:ok, %GmTicket{id: 1}} = GmTickets.create(42, "Tester", 1, "Help", 0, {0.0, 0.0, 0.0}, 1_000, server)
      assert GmTickets.create(42, "Tester", 1, "Help again", 0, {0.0, 0.0, 0.0}, 2_000, server) == :exists

      assert {:ok, %GmTicket{completed?: true}} = GmTickets.respond(1, "Done", 3_000, server)
      assert {:ok, %GmTicket{id: 2}} = GmTickets.create(42, "Tester", 1, "New", 0, {0.0, 0.0, 0.0}, 4_000, server)
    end
  end

  describe "view/2" do
    test "shows the oldest open ticket and the last change", %{server: server} do
      {:ok, _} = GmTickets.create(1, "First", 1, "A", 0, {0.0, 0.0, 0.0}, 1_000, server)
      {:ok, _} = GmTickets.create(2, "Second", 2, "B", 0, {0.0, 0.0, 0.0}, 5_000, server)

      assert %View{ticket: %GmTicket{message: "B"}, oldest_at: 1_000, last_change: 5_000} = GmTickets.view(2, server)
      assert GmTickets.view(3, server) == nil
    end
  end

  describe "update_text/5 and abandon/2" do
    test "edits open tickets, reports answered ones, and abandons", %{server: server} do
      {:ok, _} = GmTickets.create(42, "Tester", 1, "Help", 0, {0.0, 0.0, 0.0}, 1_000, server)
      assert {:ok, %GmTicket{message: "More help"}} = GmTickets.update_text(42, 2, "More help", 2_000, server)

      {:ok, _} = GmTickets.respond(1, "Done", 3_000, server)
      assert {:completed, %GmTicket{}} = GmTickets.update_text(42, 2, "Hello?", 4_000, server)

      assert GmTickets.abandon(42, server) == :ok
      assert GmTickets.abandon(42, server) == :none
      assert GmTickets.update_text(42, 2, "Gone", 5_000, server) == :error
    end
  end
end
