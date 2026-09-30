defmodule ThistleTea.Game.World.Entity.Player.SpellGroupItemsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Inventory
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.StackRules
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.Spell.TargetCodec
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Inbound
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.State
  alias ThistleTea.Game.World.Entity.Player.UsableItems
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Metadata

  setup [:scroll]

  describe "handle/3" do
    test "an active upgrade preserves the item, mana, and cooldowns", context do
      {character, _} = Aura.apply_spell(context.state.character, context.state.guid, 60, stronger(), Time.now())
      state = %{context.state | character: character}
      assert_rejected(state, state.guid, context)
    end

    test "another recipient's current aura prevents scroll consumption", context do
      guid = context.state.guid + 1_000_000
      {target, _} = Aura.apply_spell(context.state.character, guid, 60, stronger(), Time.now())
      Metadata.put(guid, %{alive?: true, aura_sources: Aura.source_spells(target)})
      on_exit(fn -> Metadata.delete(guid) end)
      assert_rejected(context.state, guid, context)
    end
  end

  defp assert_rejected(state, target_guid, context) do
    message = %Inbound.CmsgUseItem{
      bag: Inventory.bag_0(),
      slot: 23,
      spell_count: 1,
      targets: TargetCodec.encode(Target.unit(target_guid))
    }

    done = use_item(message, state, fn _id -> context.spell end)
    assert done.character.internal.casting == nil
    assert done.character.internal.cooldowns == state.character.internal.cooldowns
    assert done.character.unit.power1 == 100
    assert ItemStore.get(context.item.object.guid).item.stack_count == 3
    assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 2, reason: 0x07}}}
  end

  defp scroll(_context) do
    guid = System.unique_integer([:positive, :monotonic])

    item =
      ItemStore.create(%ItemTemplate{entry: 998_411, stackable: 20, spellid_1: 8118, spellcharges_1: -1},
        owner: guid,
        stack_count: 3
      )

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: %Player{inv1: item.object.guid},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{health: 100, max_health: 100, level: 60, class: 8, race: 1, power1: 100, max_power1: 100, auras: []}
    }

    on_exit(fn -> ItemStore.delete(item.object.guid) end)

    %{
      item: item,
      state: %State{ready: true, guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character},
      spell: %Spell{
        id: 8118,
        mana_cost: 10,
        power_type: 0,
        stack_rules: %StackRules{stronger: MapSet.new([12_179])},
        effects: [
          %Effect{type: :apply_aura, aura: :mod_stat, base_points: 5, misc_value: 0, implicit_target_a: :target_ally}
        ]
      }
    }
  end

  defp stronger do
    %Spell{
      id: 12_179,
      duration_ms: 60_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mod_stat, base_points: 17, misc_value: 0}]
    }
  end

  defp use_item(%{bag: bag, slot: slot, targets: targets}, state, load_spell),
    do: UsableItems.use(state, {bag, slot}, targets, load_spell)
end
