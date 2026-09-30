defmodule ThistleTea.Game.Inbound.CmsgSummonResponseTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Inbound.CmsgSummonResponse

  test "decodes the Vanilla summoner guid" do
    assert CmsgSummonResponse.from_binary(<<123::little-size(64)>>) ==
             %CmsgSummonResponse{summoner_guid: 123}
  end
end
