defmodule ThistleTea.Game.Entity.Server.Mob.PocketsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot, as: InternalLoot
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Loot.Actor
  alias ThistleTea.Game.Entity.Logic.Loot.Commit
  alias ThistleTea.Game.Entity.Logic.LootSession
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.Entity.Server.Mob.Pockets
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Loot, as: LootLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @loot_id 999_451
  @item 999_452
  @quest_item 999_453

  setup [:loot_fixture]

  describe "open/3" do
    test "reopens the same private loot without rerolling money", %{mob: mob, actor: actor} do
      assert {{:ok, loot}, mob} = Pockets.open(mob, actor, 60)
      assert loot.gold in 0..600
      assert rem(loot.gold, 10) == 0
      assert length(loot.items) == 2
      assert {{:ok, ^loot}, mob} = Pockets.open(Pockets.release(mob, actor), actor, 60)
      assert mob.internal.loot.session == nil
      assert mob.unit.dynamic_flags == 0
      assert mob.internal.loot.tapped_by == nil
      assert {{:error, :no_loot}, _} = Corpse.view(mob, actor)
    end

    test "later rogues get only their quest drops, even in the same party", %{mob: mob, actor: actor} do
      {{:ok, _}, mob} = Pockets.open(mob, actor, 60)
      other = %{actor | guid: actor.guid + 1}
      assert {{:ok, loot}, mob} = Pockets.open(mob, other, 60)
      assert loot.gold == 0
      assert [%{item_id: @quest_item}] = loot.items
      refute LootSession.tap_allowed?(mob.internal.loot.pockets[actor.guid], other)
      stranger = %{other | guid: other.guid + 1, needed_items: MapSet.new()}
      assert {{:error, :nothing_to_take}, _} = Pockets.open(mob, stranger, 60)
    end

    test "rejects dead, distant and pocketless creatures", %{mob: mob, actor: actor} do
      assert {{:error, :no_loot}, _} = Pockets.open(%{mob | unit: %{mob.unit | health: 0}}, actor, 60)
      assert {{:error, :no_loot}, _} = Pockets.open(mob, %{actor | distance: 5.01}, 60)
      assert {{:error, :no_loot}, _} = Pockets.open(mob, %{actor | distance: nil}, 60)
      mob = put_in(mob.internal.loot.pickpocket_id, 0)
      assert {{:error, :no_loot}, _} = Pockets.open(mob, actor, 60)
    end
  end

  describe "interact/4" do
    test "empty pockets never regenerate ordinary items or money", %{mob: mob, actor: actor} do
      {{:ok, _}, mob} = Pockets.open(mob, actor, 60)
      mob = put_in(mob.internal.loot.pockets[actor.guid].loot.gold, 0)

      mob =
        Enum.reduce([0, 1], mob, fn slot, mob ->
          {{:ok, reservation}, mob} = Pockets.interact(mob, actor, {:reserve_item, slot}, self())
          {:ok, mob} = Pockets.commit(mob, %Commit{token: reservation.token, actor_guid: actor.guid})
          mob
        end)

      assert {{:error, :nothing_to_take}, _} = Pockets.open(Pockets.release(mob, actor), actor, 60)
    end

    test "requires an open session and consumes money once", %{mob: mob, actor: actor} do
      assert {{:error, :no_loot}, _} = Pockets.interact(mob, actor, :take_gold, self())
      {{:ok, _}, mob} = Pockets.open(mob, actor, 60)
      mob = put_in(mob.internal.loot.pockets[actor.guid].loot.gold, 123)
      assert {{:ok, 123}, mob} = Pockets.interact(mob, actor, :take_gold, self())
      assert {{:error, :no_gold}, _} = Pockets.interact(mob, actor, :take_gold, self())
      mob = Pockets.release(mob, actor)
      assert {{:error, :no_loot}, _} = Pockets.interact(mob, actor, {:reserve_item, 0}, self())
      {{:ok, loot}, _} = Pockets.open(mob, actor, 60)
      assert loot.gold == 0
    end

    test "reserves once and restores items when the receiver disappears", %{mob: mob, actor: actor} do
      {{:ok, _}, mob} = Pockets.open(mob, actor, 60)
      owner = spawn(fn -> receive do: (:stop -> :ok) end)
      {{:ok, reservation}, mob} = Pockets.interact(mob, actor, {:reserve_item, 0}, owner)
      assert Pockets.pending?(mob)
      assert {{:error, :already_looted}, _} = Pockets.interact(mob, actor, {:reserve_item, 0}, self())
      Process.exit(owner, :kill)
      assert_receive {:DOWN, token, :process, ^owner, :killed}
      assert token == reservation.token
      mob = Pockets.reservation_lost(mob, token)
      refute Pockets.pending?(mob)
      assert {{:ok, reservation}, mob} = Pockets.interact(mob, actor, {:reserve_item, 0}, self())
      assert :ok = Pockets.validate_commit(mob, actor, reservation.token)
      command = %Commit{token: reservation.token, actor_guid: actor.guid}
      assert {:ok, mob} = Pockets.commit(mob, command)
      assert {{:error, :invalid_reservation}, _} = Pockets.commit(mob, command)
      assert {{:error, :already_looted}, _} = Pockets.interact(mob, actor, {:reserve_item, 0}, self())
    end

    test "death closes pockets without losing pending transfers or corpse loot", %{mob: mob, actor: actor} do
      {{:ok, _}, mob} = Pockets.open(mob, actor, 60)
      {{:ok, reservation}, mob} = Pockets.interact(mob, actor, {:reserve_item, 0}, self())

      mob = %{
        mob
        | unit: %{mob.unit | health: 0},
          internal: %{mob.internal | damage_origin: %{mob.internal.damage_origin | player: 100}}
      }

      mob = Corpse.prepare(mob, actor.guid)
      assert Pockets.pending?(mob)
      assert Corpse.pending?(mob)
      assert {{:error, :no_loot}, _} = Pockets.interact(mob, actor, :take_gold, self())
      assert {{:error, :no_loot}, _} = Pockets.open(mob, actor, 60)
      assert {:ok, mob} = Pockets.commit(mob, %Commit{token: reservation.token, actor_guid: actor.guid})
      refute Corpse.pending?(mob)
      assert {{:ok, loot}, mob} = Corpse.view(mob, actor)
      assert loot.gold == 17
      assert [%{item_id: @item, count: 2}] = loot.items
      respawned = Mob.respawn(mob)
      assert respawned.internal.loot.pockets == nil
      assert {{:ok, fresh}, _} = Pockets.open(respawned, actor, 60)
      assert length(fresh.items) == 2
    end
  end

  defp loot_fixture(_) do
    ItemLoader.init()
    LootLoader.init()

    for id <- [@item, @quest_item],
        do: :ets.insert(ItemLoader, {id, %ItemTemplate{entry: id, name: "Pocket item", quality: 1}})

    rows =
      for {id, chance} <- [{@item, 100.0}, {@quest_item, -100.0}],
          do: %{item: id, chance: chance, groupid: 0, mincount_or_ref: 1, maxcount: 1}

    :ets.insert(LootLoader, {{:pickpocket, @loot_id}, rows})
    guid = Guid.from_low_guid(:mob, 299, System.unique_integer([:positive, :monotonic]))
    actor = %Actor{guid: 41, group_id: 1, needed_items: MapSet.new([@quest_item]), distance: 2.0}

    mob = %Mob{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, level: 60, dynamic_flags: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        loot: %InternalLoot{pickpocket_id: @loot_id, override: %{items: [{@item, 2}], gold: 17}}
      }
    }

    on_exit(fn ->
      :ets.delete(LootLoader, {:pickpocket, @loot_id})
      for id <- [@item, @quest_item], do: :ets.delete(ItemLoader, id)
      Metadata.delete(guid)
    end)

    %{mob: mob, actor: actor}
  end
end
