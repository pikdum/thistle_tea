defmodule ThistleTea.Game.Network.Message.CmsgPageTextQueryTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Network.Message.CmsgPageTextQuery
  alias ThistleTea.Game.World.Loader.PageText, as: PageTextLoader

  setup do
    PageTextLoader.init()
    :ok
  end

  defp seed_page(entry, page), do: :ets.insert(PageTextLoader, {entry, page})

  describe "from_binary/1" do
    test "parses the page id and ignores the trailing guid" do
      assert %CmsgPageTextQuery{page_id: 42} =
               CmsgPageTextQuery.from_binary(<<42::little-size(32), 0::little-size(64)>>)
    end
  end

  describe "handle/2" do
    test "sends every page in the chain" do
      seed_page(9101, %{text: "Page one.", next_page: 9102})
      seed_page(9102, %{text: "Page two.", next_page: 0})

      CmsgPageTextQuery.handle(%CmsgPageTextQuery{page_id: 9101}, %{})

      assert_received {:"$gen_cast",
                       {:send_packet,
                        %Message.SmsgPageTextQueryResponse{page_id: 9101, text: "Page one.", next_page: 9102}}}

      assert_received {:"$gen_cast",
                       {:send_packet,
                        %Message.SmsgPageTextQueryResponse{page_id: 9102, text: "Page two.", next_page: 0}}}
    end

    test "sends a placeholder for missing pages" do
      seed_page(9103, nil)

      CmsgPageTextQuery.handle(%CmsgPageTextQuery{page_id: 9103}, %{})

      assert_received {:"$gen_cast",
                       {:send_packet,
                        %Message.SmsgPageTextQueryResponse{page_id: 9103, text: "Item page missing.", next_page: 0}}}
    end

    test "stops on page cycles" do
      seed_page(9104, %{text: "Loop.", next_page: 9104})

      CmsgPageTextQuery.handle(%CmsgPageTextQuery{page_id: 9104}, %{})

      assert_received {:"$gen_cast", {:send_packet, %Message.SmsgPageTextQueryResponse{page_id: 9104}}}
      refute_received {:"$gen_cast", {:send_packet, %Message.SmsgPageTextQueryResponse{page_id: 9104}}}
    end
  end

  describe "wire formats" do
    test "page text response packs id, text, and next page" do
      binary =
        Message.SmsgPageTextQueryResponse.to_binary(%Message.SmsgPageTextQueryResponse{
          page_id: 7,
          text: "Hello",
          next_page: 8
        })

      assert binary == <<7::little-size(32)>> <> "Hello" <> <<0>> <> <<8::little-size(32)>>
    end

    test "read item ok repeats the guid" do
      assert Message.SmsgReadItemOk.to_binary(%Message.SmsgReadItemOk{guid: 5}) ==
               <<5::little-size(64), 5::little-size(64)>>
    end

    test "read item failed wraps the reason in guids" do
      assert Message.SmsgReadItemFailed.to_binary(%Message.SmsgReadItemFailed{guid: 5}) ==
               <<5::little-size(64), 0, 5::little-size(64)>>
    end
  end
end
