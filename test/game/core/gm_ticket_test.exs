defmodule ThistleTea.Game.Core.GmTicketTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.GmTicket

  setup do
    %{ticket: GmTicket.new(7, 42, "Tester", 1, "I am stuck", 0, {1.0, 2.0, 3.0}, 1_000)}
  end

  describe "update_text/4" do
    test "edits an open ticket and refuses an answered one", %{ticket: ticket} do
      assert {:ok, %GmTicket{type: 8, message: "Still stuck", modified_at: 2_000}} =
               GmTicket.update_text(ticket, 8, "Still stuck", 2_000)

      assert GmTicket.update_text(GmTicket.respond(ticket, "Try .start", 2_000), 8, "Hello?", 3_000) == :error
      assert GmTicket.update_text(ticket, 11, "Bad category", 2_000) == :error
    end
  end

  describe "display_message/1" do
    test "appends the answer below a completed ticket", %{ticket: ticket} do
      assert GmTicket.display_message(ticket) == "I am stuck"

      message = ticket |> GmTicket.respond("Try .start", 2_000) |> GmTicket.display_message()
      assert message =~ ~r/^I am stuck\n\n-+\nCustomer ticket #7 completed.\n\n    GM answer:\nTry \.start$/
    end
  end

  describe "age_days/2" do
    test "reports elapsed time in days" do
      assert GmTicket.age_days(0, 43_200_000) == 0.5
      assert GmTicket.age_days(nil, 43_200_000) == 0.0
    end
  end
end
