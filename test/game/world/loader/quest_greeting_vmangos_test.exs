defmodule ThistleTea.Game.World.Loader.QuestGreetingVmangosTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.World.Loader.QuestGreeting, as: QuestGreetingLoader
  alias ThistleTea.Game.World.Loader.QuestGreeting.Greeting

  @moduletag :vmangos_db

  describe "load_all/1" do
    test "keys creature greetings by entry with their emote" do
      table = :ets.new(__MODULE__, [:set, :public])
      QuestGreetingLoader.load_all(table)

      assert %Greeting{text: "Hello there, $c." <> _rest, emote: 1} = QuestGreetingLoader.get(:unit, 823, table)
      assert QuestGreetingLoader.get(:game_object, 823, table) == nil
    end
  end
end
