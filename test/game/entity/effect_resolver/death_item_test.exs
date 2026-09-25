defmodule ThistleTea.Game.Entity.EffectResolver.DeathItemTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.DeathItem
  alias ThistleTea.Game.Entity.Logic.Aura.DeathItem, as: DeathItemLogic
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  setup [:reward]

  describe "resolve/2" do
    test "rewards the original tap owner using the current caster level", %{reward: reward, opts: opts} do
      assert [%Effects.GiveItem{target_guid: 7, item_id: 6265, count: 1}] = DeathItem.resolve(reward, opts)
      assert [] = DeathItem.resolve(reward, Keyword.put(opts, :metadata, fn 7 -> %{level: 60} end))
    end

    test "rewards current members of the original tap group", %{reward: reward, opts: opts} do
      reward = %{reward | victim: %{reward.victim | tap: %Tap{player: 8, group_id: 42}}}
      assert [] = DeathItem.resolve(reward, opts)
      assert [_reward] = DeathItem.resolve(reward, Keyword.put(opts, :group_of, fn 7 -> %Group{id: 42} end))
      assert [] = DeathItem.resolve(reward, Keyword.put(opts, :group_of, fn 7 -> %Group{id: 43} end))
      untapped = %{reward | victim: %{reward.victim | tap: nil}}
      assert [] = DeathItem.resolve(untapped, Keyword.put(opts, :group_of, fn 7 -> %Group{id: 42} end))
    end

    test "a later group does not inherit a solo tap", %{reward: reward, opts: opts} do
      reward = %{reward | victim: %{reward.victim | tap: %Tap{player: 8}}}
      assert [] = DeathItem.resolve(reward, Keyword.put(opts, :group_of, fn 7 -> %Group{id: 42} end))
    end

    test "battleground participants can receive shards without a personal creature tap", %{reward: reward, opts: opts} do
      world = WorldRef.instance(30, 1)
      reward = %{reward | victim: %{reward.victim | tap: %Tap{player: 8}}}

      opts =
        Keyword.merge(opts,
          position: fn 7 -> {world, 0, 0, 0} end,
          participants: fn ^world -> %{7 => %{team: :alliance}} end
        )

      assert [_reward] = DeathItem.resolve(reward, opts)
    end

    test "rejects missing casters and creatures without redirecting to their owners", %{reward: reward, opts: opts} do
      assert [] = DeathItem.resolve(reward, Keyword.put(opts, :metadata, fn 7 -> nil end))
      pet = Guid.from_low_guid(:pet, 416, 1)

      assert [] =
               DeathItem.resolve(
                 %{reward | target_guid: pet},
                 Keyword.put(opts, :metadata, fn ^pet -> %{level: 10, owner_guid: 7} end)
               )
    end

    test "allows non-gray player victims without a creature tap", %{opts: opts} do
      player = %Character{unit: %Unit{level: 10, auras: [holder()]}, player: %Player{}}
      [reward] = DeathItemLogic.reward_events(player)
      assert [_reward] = DeathItem.resolve(reward, opts)
      assert [] = DeathItem.resolve(reward, Keyword.put(opts, :metadata, fn 7 -> %{level: 60} end))
    end

    test "rejects pet, totem, and zero-experience creatures for shards", %{mob: mob, opts: opts} do
      pet = %{mob | object: %{mob.object | guid: Guid.from_low_guid(:pet, 416, 1)}}
      totem = %{mob | internal: %{mob.internal | totem: %Totem{}}}
      no_xp = %{mob | internal: %{mob.internal | creature: %Creature{experience_multiplier: 0.0}}}

      for victim <- [pet, totem, no_xp] do
        [reward] = DeathItemLogic.reward_events(victim)
        assert [] = DeathItem.resolve(reward, opts)
        assert [_reward] = DeathItem.resolve(%{reward | item_id: 6435}, opts)
      end
    end

    test "capture items ignore gray level and tap ownership", %{reward: reward, opts: opts} do
      reward = %{reward | item_id: 6435, victim: %{reward.victim | tap: nil}}

      assert [%Effects.GiveItem{item_id: 6435}] =
               DeathItem.resolve(reward, Keyword.put(opts, :metadata, fn 7 -> %{level: 60} end))
    end
  end

  describe "reward_events/1" do
    test "keeps separate generic rewards and gives each warlock at most one shard", %{mob: mob} do
      first = holder()
      second = %{first | caster_guid: 8}

      capture = %{
        first
        | spell: %Spell{id: 7914},
          auras: [%Aura{type: :channel_death_item, item_type: 6435, amount: 2}]
      }

      mob = %{mob | unit: %{mob.unit | auras: [first, first, second, second, capture, capture]}}

      assert [{7, 6265, 1}, {8, 6265, 1}, {7, 6435, 2}, {7, 6435, 2}] ==
               Enum.map(DeathItemLogic.reward_events(mob), &{&1.target_guid, &1.item_id, &1.count})
    end

    test "ignores missing items and nonpositive quantities", %{mob: mob} do
      for {item, count} <- [{0, 1}, {nil, 1}, {6265, 0}, {6265, -1}, {6265, nil}] do
        holder = %{holder() | auras: [%Aura{type: :channel_death_item, item_type: item, amount: count}]}
        assert [] = DeathItemLogic.reward_events(%{mob | unit: %{mob.unit | auras: [holder]}})
      end
    end
  end

  defp reward(_context) do
    mob = %Mob{}

    mob = %{
      mob
      | unit: %{mob.unit | level: 10, auras: [holder()]},
        internal: %{mob.internal | loot: %Loot{tapped_by: %Tap{player: 7}}}
    }

    [reward] = DeathItemLogic.reward_events(mob)
    opts = [metadata: fn 7 -> %{level: 10} end, group_of: fn _guid -> nil end, position: fn _guid -> nil end]
    %{mob: mob, reward: reward, opts: opts}
  end

  defp holder do
    %Holder{
      spell: %Spell{id: 1120, spell_family: 5},
      caster_guid: 7,
      caster_level: 60,
      auras: [%Aura{type: :channel_death_item, item_type: 6265, amount: 1}]
    }
  end
end
