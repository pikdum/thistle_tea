defmodule ThistleTea.Game.World.PostOfficeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.PostOffice

  setup do
    start_supervised!({PostOffice, name: nil})
    |> then(&{:ok, post_office: &1})
  end

  describe "mailbox custody" do
    test "retries a keyed delivery without restoring acknowledged mail", %{post_office: post_office} do
      {token, []} = PostOffice.open(20, self(), post_office)
      attrs = %{sender_type: :auction, sender: 1, receiver: 20, subject: "auction", money: 100}
      assert {:ok, mail} = PostOffice.post_once({:auction, 1}, attrs, post_office)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^mail}}
      assert PostOffice.pending?(20, token, mail.id, post_office)
      assert :ok = PostOffice.acknowledge(20, token, [mail.id], post_office)
      refute PostOffice.pending?(20, token, mail.id, post_office)
      assert {:ok, ^mail} = PostOffice.post_once({:auction, 1}, attrs, post_office)
      refute_receive {:"$gen_cast", {:mail_delivery, ^token, _mail}}
      assert :ok = PostOffice.close(20, token, [], post_office)
      assert {_token, []} = PostOffice.open(20, self(), post_office)
    end

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

  describe "restart recovery" do
    test "retains posting identities, pending deliveries, and acknowledged custody" do
      table = :ets.new(:mail_recovery, [:public])
      spec = Supervisor.child_spec({PostOffice, name: nil, table: table}, id: :recovery)
      server = start_supervised!(spec)
      {token, []} = PostOffice.open(20, self(), server)
      attrs = %{sender: 10, receiver: 20, subject: "delivery"}
      assert {:ok, pending} = PostOffice.post_once(:pending, attrs, server)
      assert {:ok, claimed} = PostOffice.post_once(:claimed, attrs, server)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^pending}}
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^claimed}}
      PostOffice.acknowledge(20, token, [claimed.id], server)
      stop_supervised!(:recovery)

      server = start_supervised!(spec)
      assert_receive {:"$gen_cast", {:mail_delivery, ^token, ^pending}}
      refute_receive {:"$gen_cast", {:mail_delivery, ^token, ^claimed}}
      assert {:ok, ^pending} = PostOffice.post_once(:pending, attrs, server)
      assert {:ok, ^claimed} = PostOffice.post_once(:claimed, attrs, server)
      assert {:ok, next} = PostOffice.post(attrs, server)
      assert next.id > claimed.id
      assert {_new_token, [^pending, ^next]} = PostOffice.open(20, self(), server)
    end
  end

  defp post(post_office, receiver) do
    PostOffice.post(
      %{sender: 10, receiver: receiver, subject: "hello", deliver_at: 1_000, expire_at: 2_000},
      post_office
    )
  end
end
