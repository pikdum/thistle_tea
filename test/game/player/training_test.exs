defmodule ThistleTea.Game.Player.TrainingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.TrainerSpell
  alias ThistleTea.Game.Entity.Logic.Skills
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgTrainerBuySpell
  alias ThistleTea.Game.Network.Message.SmsgTrainerList
  alias ThistleTea.Game.Player.Training
  alias ThistleTea.Game.World.Loader.Gossip
  alias ThistleTea.Game.World.Loader.Trainer
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  @entry 999_170

  setup [:trainer]

  describe "send_list/2 and buy/3" do
    test "advertises the limit and rejects a forged purchase without charging", %{state: state, guid: guid} do
      assert Training.valid_trainer?(state.character, guid)
      assert Training.send_list(state, guid) == state
      assert_received {:"$gen_cast", {:send_packet, %SmsgTrainerList{spells: [spell]}}}
      assert spell.state == :green_disabled
      assert spell.profession_slots == 0
      assert spell.profession_slots_required == 1
      message = %CmsgTrainerBuySpell{trainer_guid: guid, spell_id: 2275}
      assert CmsgTrainerBuySpell.handle(message, state) == state
      assert state.character.player.coinage == 100
      refute_received {:"$gen_cast", {:send_packet, _message}}

      player = state.character.player
      changed = %{state | character: %{state.character | player: %{player | skills: Map.delete(player.skills, 186)}}}
      Training.send_list(changed, guid)
      assert_received {:"$gen_cast", {:send_packet, %SmsgTrainerList{spells: [spell]}}}
      assert spell.state == :green
      assert spell.profession_slots == 1
    end

    test "requires a live nearby trainer in the same world", %{state: state, guid: guid} do
      for {world, x} <- [{WorldRef.open(0), 6.0}, {WorldRef.open(1), 2.0}, {WorldRef.instance(0, 1), 2.0}] do
        SpatialHash.update(:mobs, guid, world, x, 0.0, 0.0)
        refute Training.valid_trainer?(state.character, guid)
        assert Training.send_list(state, guid) == state
        assert Training.buy(state, guid, 2275) == state
      end

      refute_received {:"$gen_cast", {:send_packet, _message}}
    end

    test "rejects dead players, inaccessible NPCs and wrong trainer classes", %{state: state, guid: guid} do
      dead = %{state.character | unit: %{state.character.unit | health: 0}}
      refute Training.valid_trainer?(dead, guid)

      for metadata <- [
            %{alive?: false, npc_flags: 0x10},
            %{alive?: true, npc_flags: 0},
            %{alive?: true, npc_flags: 0x10, in_combat: true},
            %{alive?: true, npc_flags: 0x10, unit_flags: 0x02000000},
            %{alive?: true, npc_flags: 0x10, owner_guid: state.guid}
          ] do
        Metadata.put(guid, metadata)
        refute Training.valid_trainer?(state.character, guid)
      end

      Metadata.put(guid, %{alive?: true, npc_flags: 0x10})
      :ets.insert(Gossip, {{:trainer, @entry}, %{type: 0, class: 8, race: 0}})
      refute Training.valid_trainer?(state.character, guid)
    end
  end

  defp trainer(_context) do
    owner = System.unique_integer([:positive, :monotonic])
    guid = Guid.from_low_guid(:mob, @entry, owner)
    {:ok, _} = Entity.register(guid)
    :ets.insert(Gossip, {{:trainer, @entry}, %{type: 2, class: 0, race: 0}})
    spell = %TrainerSpell{teach_spell_id: 2275, learned_spell_id: 2259, skill_id: 171, skill_max: 75, cost: 10}
    :ets.insert(Trainer, {@entry, %{trainer_type: 2, spells: [spell]}})
    Metadata.put(guid, %{alive?: true, npc_flags: 0x10})
    SpatialHash.update(:mobs, guid, WorldRef.open(0), 2.0, 0.0, 0.0)

    character = %Character{
      id: owner,
      object: %Object{guid: owner},
      player: %Player{coinage: 100, skills: %{} |> Skills.learn_rank(186, 75) |> Skills.learn_rank(182, 75)},
      unit: %Unit{health: 100, max_health: 100, level: 60, class: 1, race: 1, auras: []},
      internal: %Internal{spells: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    on_exit(fn ->
      :ets.delete(Gossip, {:trainer, @entry})
      :ets.delete(Trainer, @entry)
      Metadata.delete(guid)
      SpatialHash.remove(:mobs, guid)
    end)

    %{state: %State{guid: owner, ready: true, character: character}, guid: guid}
  end
end
