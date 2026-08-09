defmodule ThistleTea.Game.World.Loader.BroadcastTextVMangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.BroadcastText

  @moduletag :vmangos_db

  test "loads the Stratholme instance callback texts" do
    table = :ets.new(:instance_broadcast_text_test, [:set, :public])
    assert :ok = BroadcastText.load_all([11_812, 11_816], table)

    assert %{text: "Intruders!" <> _, chat_type: :zone_yell} = BroadcastText.get(11_812, table)
    assert %{text: "Don't worry about me!" <> _, chat_type: :zone_yell} = BroadcastText.get(11_816, table)
  end
end
