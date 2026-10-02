defmodule ThistleTea.Game.World.Entity.Player.QuestGreetingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.Player.Quests
  alias ThistleTea.Game.World.Loader.Gossip, as: GossipLoader
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.NpcText, as: NpcTextLoader
  alias ThistleTea.Game.World.Loader.QuestGreeting, as: QuestGreetingLoader
  alias ThistleTea.Game.World.Loader.QuestGreeting.Greeting
  alias ThistleTea.Test.Unique

  setup [:character]

  describe "greeting/2" do
    test "prefers the giver's quest greeting", %{character: character} do
      entry = Unique.integer()
      greeting = %Greeting{text: "Hello there, $c.", emote: 1, emote_delay: 0}
      :ok = QuestGreetingLoader.put(:unit, entry, greeting)
      on_exit(fn -> :ets.delete(QuestGreetingLoader, {:unit, entry}) end)

      assert Quests.greeting(npc_guid(entry), character) == greeting
    end

    test "falls back to the giver's gossip text", %{character: character} do
      entry = Unique.integer()
      menu_id = Unique.integer()
      text_id = Unique.integer()
      seed_gossip(entry, menu_id, text_id, %{text_0: "", text_1: "Welcome, traveler.", em_0: 2, em_0_delay: 100})

      assert Quests.greeting(npc_guid(entry), character) ==
               %Greeting{text: "Welcome, traveler.", emote: 2, emote_delay: 100}
    end

    test "stays blank for placeholder gossip and unknown givers", %{character: character} do
      entry = Unique.integer()
      menu_id = Unique.integer()
      seed_gossip(entry, menu_id, 68, nil)

      assert Quests.greeting(npc_guid(entry), character) == %Greeting{}
      assert Quests.greeting(npc_guid(Unique.integer()), character) == %Greeting{}
    end
  end

  defp seed_gossip(entry, menu_id, text_id, group) do
    :ets.insert(GossipLoader, {{:menu, menu_id}, %Menu{menu_id: menu_id, text_id: text_id}})
    :ets.insert(GossipLoader, {{:creature_menu, entry}, menu_id})
    if group, do: :ets.insert(NpcTextLoader, {text_id, [group]})

    on_exit(fn ->
      :ets.delete(GossipLoader, {:menu, menu_id})
      :ets.delete(GossipLoader, {:creature_menu, entry})
      if group, do: :ets.delete(NpcTextLoader, text_id)
    end)
  end

  defp npc_guid(entry), do: Guid.from_low_guid(:unit, entry, Unique.integer())

  defp character(_context) do
    character = %Character{
      object: %Object{guid: Unique.integer()},
      unit: %Unit{health: 100, max_health: 100, auras: []},
      player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }

    %{character: character}
  end
end
