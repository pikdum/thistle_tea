defmodule ThistleTea.Game.World.Entity.Player.GossipTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest
  alias ThistleTea.Game.Core.Quest.QuestLog
  alias ThistleTea.Game.Core.Reputation
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgGossipComplete
  alias ThistleTea.Game.Network.Message.SmsgGossipMessage
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Player.Gossip
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Loader.Gossip.Menu
  alias ThistleTea.Game.World.Loader.Gossip.Option
  alias ThistleTea.Game.World.Loader.Gossip.Text
  alias ThistleTea.Game.World.Loader.Quest, as: QuestLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Test.Unique

  describe "send_menu/4" do
    test "starts the shown greeting's script on its speaker" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 11_627, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)

      steps = [%ScriptStep{command: :quest_credit, swap_initial?: true}]
      menu = %Menu{menu_id: 3650, texts: [%Text{text_id: 4449, condition_id: 0, script_steps: steps}]}

      Gossip.send_menu(creature_guid, menu, [], %{character: character(player_guid)})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{title_text_id: 4449}}}
      assert_receive {:"$gen_cast", {:start_script, ^steps, ^player_guid}}
    end

    test "offers an option once a script grants the creature the flag it needs" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 12_018, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)
      on_exit(fn -> Metadata.delete(creature_guid) end)

      option = %Option{id: 0, option_id: 1, npc_flag: 1, action_menu_id: 4109, text: "Tell me more."}
      menu = %Menu{menu_id: 4093, texts: [%Text{text_id: 4995, condition_id: 0}], options: [option]}
      state = %{character: character(player_guid)}

      Metadata.put(creature_guid, %{alive?: true, npc_flags: 0})
      Gossip.send_menu(creature_guid, menu, [], state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{gossips: []}}}

      Metadata.update(creature_guid, %{npc_flags: 1})
      Gossip.send_menu(creature_guid, menu, [], state)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{gossips: [%{message: "Tell me more."}]}}}
    end

    test "starts nothing for a greeting without a script" do
      player_guid = Guid.from_low_guid(:player, Unique.integer())
      creature_guid = Guid.from_low_guid(:mob, 68, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)

      menu = %Menu{menu_id: 1, texts: [%Text{text_id: 2, condition_id: 0}]}

      Gossip.send_menu(creature_guid, menu, [], %{character: character(player_guid)})

      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipMessage{title_text_id: 2}}}
      refute_receive {:"$gen_cast", {:start_script, _steps, _target}}, 50
    end
  end

  describe "select/3" do
    test "credits talking to the speaker only when its closing option asks to" do
      id = Unique.integer()
      player_guid = Guid.from_low_guid(:player, id)
      creature_guid = Guid.from_low_guid(:mob, 6669, Unique.integer())
      {:ok, _owner} = Entity.register(creature_guid)
      quest = %Quest{id: 900_000 + Unique.integer(), required_kills: [{0, 6669, 1}]}
      :ets.insert(QuestLoader, {{:quest, quest.id}, quest})
      {:ok, log} = QuestLog.add(%{}, quest.id)
      character = character(player_guid)
      character = %{character | id: id, player: %{character.player | quest_log: log}}

      on_exit(fn ->
        :ets.delete(QuestLoader, {:quest, quest.id})
        CharacterStore.delete(id)
      end)

      scripted = %Option{id: 0, option_id: 1, action_menu_id: -1, talk_credit?: false}
      options = [scripted, %{scripted | id: 1, talk_credit?: true}]
      state = %State{guid: player_guid, character: character, gossip_menu_guid: creature_guid}
      state = %{state | gossip_menu_options: options}

      closed = Gossip.select(state, creature_guid, 0)
      assert_receive {:"$gen_cast", {:send_packet, %SmsgGossipComplete{}}}
      assert QuestLog.get(closed.character.player.quest_log, quest.id).counts == %{}

      talked = Gossip.select(state, creature_guid, 1)
      assert QuestLog.get(talked.character.player.quest_log, quest.id).counts == %{0 => 1}
    end
  end

  defp character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, power1: 0, max_power1: 0, auras: []},
      player: %Player{skills: %{}, quest_log: %{}, rewarded_quests: MapSet.new(), reputation: %Reputation{}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0), spellbook: %{}}
    }
  end
end
