defmodule ThistleTea.Game.Entity.Logic.Trade.OpeningTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Lock
  alias ThistleTea.Game.Entity.Data.Lock.Requirement
  alias ThistleTea.Game.Entity.Data.Trade.Cast, as: TradeCast
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Trade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_opening]

  describe "plan/5" do
    test "unlocks a retained bound item and awards skill together with payment", context do
      assert {:ok, exchange} = plan(context)
      caster = exchange.changes[1]
      owner = exchange.changes[2]
      target = ChangeSet.get_item(owner, 201, context.lookup)
      assert target.item.owner == 2
      assert target.item.flags == 5
      assert owner.player.inv1 == 201
      refute Item.loot_generated?(target)
      assert exchange.outgoing == %{1 => [], 2 => []}
      assert caster.player.coinage == 1500
      assert owner.player.coinage == 500
      assert caster.player.skills[633].value == 2
      assert context.lookup.(201).item.flags == 1
      assert context.characters[1].player.skills[633].value == 1
      assert plan(context) == {:ok, exchange}
    end

    test "revalidates skill, tools, knowledge and caster life at acceptance", context do
      caster = context.characters[1]

      changed = [
        {%{caster | player: %{caster.player | skills: %{}}}, :low_castlevel},
        {%{caster | player: %{caster.player | inv1: 0}}, :item_gone},
        {%{caster | internal: %{caster.internal | spellbook: %{}}}, :not_known},
        {%{caster | unit: %{caster.unit | health: 0}}, :caster_dead}
      ]

      for {character, reason} <- changed do
        assert {:error, 1, {:cast, 1804, ^reason}} =
                 plan(%{context | characters: %{context.characters | 1 => character}})
      end
    end

    test "rejects stale source instances, already unlocked sources and mismatched locks", context do
      unlocked = Item.unlock(context.target)
      lookup = fn guid -> if guid == 201, do: unlocked, else: context.lookup.(guid) end
      assert {:error, 2, :item_not_found} = plan(%{context | lookup: lookup})
      assert {:ok, trade} = Trade.clear_item(context.trade, 2, 6, 0)
      assert {:ok, trade} = Trade.put_item(trade, 2, 6, unlocked, 0)
      assert {:ok, trade} = Trade.cast(trade, 1, context.cast, 0)
      assert {:error, 1, {:cast, 1804, :already_open}} = plan(%{context | trade: trade, lookup: lookup})
      cast = %{context.cast | lock: %{context.cast.lock | id: 6}}
      assert {:ok, trade} = Trade.cast(context.trade, 1, cast, 0)
      assert {:error, 1, {:cast, 1804, :bad_targets}} = plan(%{context | trade: trade})
    end

    test "a queued key consumes one charge only in the successful exchange", context do
      context = with_key(context)
      assert {:ok, exchange} = plan(context)
      caster = exchange.changes[1]
      assert ChangeSet.get_item(caster, 103, context.lookup).item.stack_count == 1
      assert caster.player.skills[633].value == 1
      assert Item.unlocked?(ChangeSet.get_item(exchange.changes[2], 201, context.lookup))
      assert context.lookup.(103).item.stack_count == 2

      character = context.characters[1]
      skills = Map.delete(character.player.skills, 164)
      character = %{character | player: %{character.player | skills: skills}}

      assert {:error, 1, {:cast, 19_646, :item_gone}} =
               plan(%{context | characters: %{context.characters | 1 => character}})

      assert {:ok, trade} = Trade.put_item(context.trade, 1, 0, context.lookup.(103), 0)
      assert {:error, 1, {:cast, 19_646, :item_gone}} = plan(%{context | trade: trade})
    end

    test "a key uses its own opening strength instead of the caster's skill", context do
      context = with_key(context)

      cast = %{
        context.cast
        | lock: %{context.cast.lock | requirements: [%Requirement{type: :skill, index: 1, skill: 70}]}
      }

      character = context.characters[1]
      skills = put_in(character.player.skills, [633, :value], 100)
      character = %{character | player: %{character.player | skills: skills}}
      assert {:ok, trade} = Trade.cast(context.trade, 1, cast, 0)

      assert {:error, 1, {:cast, 19_646, :low_castlevel}} =
               plan(%{context | trade: trade, characters: %{context.characters | 1 => character}})
    end

    test "failed recipient storage leaves the lock, key and payment untouched", context do
      context = with_key(context)
      gift = Item.build(%ItemTemplate{entry: 50}, 104, owner: 1)
      fillers = for guid <- 202..216, do: Item.build(%ItemTemplate{entry: 60}, guid, owner: 2)
      added = Map.new([gift | fillers], &{&1.object.guid, &1})
      lookup = fn guid -> Map.get(added, guid) || context.lookup.(guid) end
      caster = context.characters[1]
      owner = context.characters[2]

      fields =
        Enum.with_index(fillers, 2)
        |> Enum.map(fn {item, index} -> {String.to_atom("inv#{index}"), item.object.guid} end)

      owner = %{owner | player: struct!(owner.player, fields)}
      caster = %{caster | player: %{caster.player | inv3: 104}}
      assert {:ok, trade} = Trade.put_item(context.trade, 1, 0, gift, 0)
      context = %{context | trade: trade, lookup: lookup, characters: %{1 => caster, 2 => owner}}
      assert {:error, 2, :inventory_full} = plan(context)
      assert context.lookup.(103).item.stack_count == 2
      refute Item.unlocked?(context.lookup.(201))
      assert caster.player.coinage == 1000
      assert owner.player.coinage == 1000
    end
  end

  defp build_opening(_context) do
    spell = %Spell{
      id: 1804,
      tools: [5060],
      effects: [%Effect{type: :open_lock, misc_value: 1, base_points: -1}]
    }

    tool = Item.build(%ItemTemplate{entry: 5060}, 101, owner: 1)
    target = Item.build(%ItemTemplate{entry: 4632, flags: 4, lockid: 5, bonding: 1}, 201, owner: 2)

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{race: 1, class: 4, level: 20, health: 100},
      player: %Player{coinage: 1000, inv1: 101, skills: %{633 => %{value: 1, max: 100}}},
      internal: %Internal{spellbook: %{1804 => spell}}
    }

    owner = %Character{
      object: %Object{guid: 2},
      unit: %Unit{health: 100},
      player: %Player{coinage: 1000, inv1: 201},
      internal: %Internal{}
    }

    cast = %TradeCast{
      spell: spell,
      target_guid: 201,
      effects: [],
      lock: %Lock{id: 5, requirements: [%Requirement{type: :skill, index: 1, skill: 1}]},
      skill_roll: 0
    }

    {:ok, trade} = Trade.new(:opening, 1, 2, 0) |> Trade.open(2)
    {:ok, trade} = Trade.put_item(trade, 2, 6, target, 0)
    {:ok, trade} = Trade.money(trade, 2, 500, 0)
    {:ok, trade} = Trade.cast(trade, 1, cast, 0)
    items = %{101 => tool, 201 => target}
    %{trade: trade, cast: cast, characters: %{1 => caster, 2 => owner}, target: target, lookup: &Map.get(items, &1)}
  end

  defp with_key(context) do
    spell = %{
      context.cast.spell
      | id: 19_646,
        tools: [],
        effects: [%Effect{type: :open_lock, misc_value: 1, base_points: 24}]
    }

    key =
      Item.build(
        %ItemTemplate{
          entry: 15_869,
          required_skill: 164,
          required_skill_rank: 100,
          stackable: 20,
          spellid_1: spell.id,
          spellcharges_1: -1
        },
        103,
        owner: 1,
        stack_count: 2
      )

    character = context.characters[1]
    skills = Map.put(character.player.skills, 164, %{value: 100, max: 150})
    character = %{character | player: %{character.player | inv2: 103, skills: skills}}
    cast = %{context.cast | spell: spell, cast_item_guid: 103}
    {:ok, trade} = Trade.cast(context.trade, 1, cast, 0)
    lookup = fn guid -> if guid == 103, do: key, else: context.lookup.(guid) end
    %{context | trade: trade, cast: cast, characters: %{context.characters | 1 => character}, lookup: lookup}
  end

  defp plan(context) do
    {:ok, trade} = Trade.accept(context.trade, 1, 200)
    {:ok, trade} = Trade.accept(trade, 2, 200)
    Trade.plan(trade, context.characters, 200, context.lookup, fn _id -> nil end)
  end
end
