defmodule ThistleTea.Game.World.PostOfficeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.PostOffice

  setup do
    start_supervised!({PostOffice, name: nil})
    |> then(&{:ok, post_office: &1})
  end

  describe "mailbox custody" do
    test "holds offline mail and checks an open mailbox back in", %{post_office: post_office} do
      assert {:ok, mail} = post(post_office, 20)
      assert {token, [^mail]} = PostOffice.open(20, self(), post_office)

      PostOffice.acknowledge(20, token, [mail.id], post_office)
      assert :ok = PostOffice.close(20, token, [mail], post_office)

      assert {_new_token, [^mail]} = PostOffice.open(20, self(), post_office)
    end

    test "notifies an online owner and retains mail until acknowledgement", %{post_office: post_office} do
      {token, []} = PostOffice.open(20, self(), post_office)
      assert {:ok, mail} = post(post_office, 20)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^mail}}

      assert :ok = PostOffice.close(20, token, [], post_office)
      assert {_new_token, [^mail]} = PostOffice.open(20, self(), post_office)
    end

    test "removes acknowledged deliveries from offline custody", %{post_office: post_office} do
      {token, []} = PostOffice.open(20, self(), post_office)
      assert {:ok, mail} = post(post_office, 20)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^mail}}

      PostOffice.acknowledge(20, token, [mail.id], post_office)
      assert :ok = PostOffice.close(20, token, [], post_office)
      assert {_new_token, []} = PostOffice.open(20, self(), post_office)
    end
  end

  defp post(post_office, receiver) do
    PostOffice.post(
      %{sender: 10, receiver: receiver, subject: "hello", deliver_at: 1_000, expire_at: 2_000},
      post_office
    )
  end
end
