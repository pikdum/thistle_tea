defmodule ThistleTea.Game.Entity.Logic.Trade.EnchantmentsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemEnchantment
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Trade.Enchantment
  alias ThistleTea.Game.Entity.Logic.Inventory.ChangeSet
  alias ThistleTea.Game.Entity.Logic.Trade
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  setup [:build_enchantment]

  describe "plan/5" do
    test "enchants a bound equipped item while exchanging payment and consuming reagents", context do
      assert {:ok, exchange} = plan(context)
      caster = exchange.changes[1]
      owner = exchange.changes[2]
      assert caster.player.coinage == 1500
      assert owner.player.coinage == 500
      assert caster.player.skills[333].value == 2
      assert ChangeSet.get_item(caster, 101, context.lookup).item.stack_count == 3
      target = ChangeSet.get_item(owner, 201, context.lookup)
      assert target.item.owner == 2
      assert target.item.flags == 1
      assert {0, 41} in Item.active_enchantments(target, 200)
      assert owner.player.chest == 201
      assert exchange.casts[1].spell.id == 7418
      assert context.lookup.(201) == context.target
      assert context.lookup.(101).item.stack_count == 4
    end

    test "offered reagents cannot also pay the enchantment cost", context do
      {:ok, trade} = Trade.put_item(context.trade, 1, 0, context.reagent, 0)
      assert {:error, 1, {:cast, 7418, :reagents}} = plan(%{context | trade: trade})
      assert context.lookup.(101).item.stack_count == 4
    end

    test "revalidates tools, spell knowledge, resource cost, and target eligibility", context do
      caster = context.characters[1]
      without_tool = %{caster | player: %{caster.player | inv2: 0}}

      assert {:error, 1, {:cast, 7418, :item_gone}} =
               plan(%{context | characters: %{context.characters | 1 => without_tool}})

      untrained = %{caster | internal: %{caster.internal | spellbook: %{}}}

      assert {:error, 1, {:cast, 7418, :not_known}} =
               plan(%{context | characters: %{context.characters | 1 => untrained}})

      exhausted = %{caster | unit: %{caster.unit | power1: 0}}

      assert {:error, 1, {:cast, 7418, :no_power}} =
               plan(%{context | characters: %{context.characters | 1 => exhausted}})

      own_only = %{context.cast | spell: %{context.cast.spell | attributes: MapSet.new([:enchant_own_item_only])}}
      {:ok, trade} = Trade.enchant(context.trade, 1, own_only, 0)
      assert {:error, 1, {:cast, 7418, :not_tradeable}} = plan(%{context | trade: trade})

      assert {:error, 1, {:cast, 7418, :not_tradeable}} =
               plan(context, fn _id -> %ItemEnchantment{id: 41, flags: 1} end)
    end

    test "changing the seventh slot clears the enchantment and acceptance", context do
      {:ok, trade} = Trade.accept(context.trade, 1, 200)
      {:ok, trade} = Trade.clear_item(trade, 2, 6, 201)
      assert trade.offers[1].spell == nil
      refute trade.offers[1].accepted?
      {:ok, trade} = Trade.put_item(trade, 2, 6, context.target, 202)
      assert trade.offers[1].spell == nil
    end

    test "plans temporary coatings and spends only one application of a cast item", context do
      spell = %{
        context.cast.spell
        | id: 25_125,
          reagents: [],
          tools: [],
          effects: [%Effect{type: :enchant_item_temporary, misc_value: 2623}]
      }

      oil =
        Item.build(%ItemTemplate{entry: 20_744, stackable: 5, spellid_1: spell.id, spellcharges_1: -1}, 103,
          owner: 1,
          stack_count: 2
        )

      caster = context.characters[1]
      characters = %{context.characters | 1 => %{caster | player: %{caster.player | inv3: 103}}}

      cast = %{
        context.cast
        | spell: spell,
          cast_item_guid: 103,
          effects: [%{type: :enchant_item_temporary, id: 2623, duration_ms: 1_800_000, charges: 0, token: :oil}]
      }

      {:ok, trade} = Trade.enchant(context.trade, 1, cast, 0)

      lookup = fn
        103 -> oil
        guid -> context.lookup.(guid)
      end

      context = %{context | trade: trade, characters: characters, lookup: lookup}
      assert {:ok, exchange} = plan(context)
      assert ChangeSet.get_item(exchange.changes[1], 103, lookup).item.stack_count == 1
      assert exchange.changes[1].player.skills[333].value == 1
      target = ChangeSet.get_item(exchange.changes[2], 201, lookup)
      assert %{id: 2623, expires_at: 1_800_200, token: :oil} = Item.temporary_enchantment(target)
      assert target.item.owner == 2
    end
  end

  defp build_enchantment(_context) do
    spell = %Spell{
      id: 7418,
      school: :arcane,
      equipped_item_class: 4,
      equipped_item_inventory_type_mask: 32,
      power_type: 0,
      mana_cost: 10,
      tools: [6218],
      reagents: [{10_940, 1}],
      effects: [%Effect{type: :enchant_item, misc_value: 41}]
    }

    reagent = Item.build(%ItemTemplate{entry: 10_940, stackable: 20}, 101, owner: 1, stack_count: 4)
    rod = Item.build(%ItemTemplate{entry: 6218}, 102, owner: 1)
    target = Item.build(%ItemTemplate{entry: 25, class: 4, inventory_type: 5, item_level: 20}, 201, owner: 2)
    target = %{target | item: %{target.item | flags: 1}}

    caster = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, power1: 100, level: 50},
      player: %Player{coinage: 1000, inv1: 101, inv2: 102, skills: %{333 => %{value: 1, max: 75}}},
      internal: %Internal{spellbook: %{7418 => spell}}
    }

    owner = %Character{
      object: %Object{guid: 2},
      unit: %Unit{health: 100},
      player: %Player{chest: 201, coinage: 1000},
      internal: %Internal{}
    }

    cast = %Enchantment{
      spell: spell,
      target_guid: 201,
      effects: [%{type: :enchant_item, id: 41}],
      recipe: %{skill_id: 333, yellow: 70, gray: 110},
      skill_roll: 0
    }

    items = %{101 => reagent, 102 => rod, 201 => target}
    {:ok, trade} = Trade.new(:enchant, 1, 2, 0) |> Trade.open(2)
    {:ok, trade} = Trade.put_item(trade, 2, 6, target, 0)
    {:ok, trade} = Trade.money(trade, 2, 500, 0)
    {:ok, trade} = Trade.enchant(trade, 1, cast, 0)

    %{
      trade: trade,
      cast: cast,
      characters: %{1 => caster, 2 => owner},
      reagent: reagent,
      target: target,
      lookup: &Map.get(items, &1)
    }
  end

  defp plan(context, get_enchantment \\ fn id -> %ItemEnchantment{id: id, flags: 0} end) do
    {:ok, trade} = Trade.accept(context.trade, 1, 200)
    {:ok, trade} = Trade.accept(trade, 2, 200)
    Trade.plan(trade, context.characters, 200, context.lookup, get_enchantment)
  end
end
