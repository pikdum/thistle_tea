defmodule ThistleTea.Game.Player.FirstAidTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Network.BinaryUtils
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.Spell.TargetCodec
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  setup [:bandages]

  describe "handle/3" do
    test "a recently bandaged player keeps the item and never starts a channel", context do
      {character, _} = Aura.apply_spell(context.state.character, context.state.guid, 60, lockout(), Time.now())
      state = %{context.state | character: character}
      assert_rejected(state, state.guid, context)
    end

    test "the recipient's live immunity prevents another player's item consumption", context do
      guid = context.state.guid + 1_000_000
      {target, _} = Aura.apply_spell(context.state.character, guid, 60, lockout(), Time.now())
      Metadata.put(guid, %{alive?: true, friendly_mechanic_immunities: Aura.friendly_mechanics(target)})
      on_exit(fn -> Metadata.delete(guid) end)
      assert_rejected(context.state, guid, context)
    end
  end

  defp assert_rejected(state, target_guid, context) do
    message = %Message.CmsgUseItem{
      bag: Inventory.bag_0(),
      slot: 23,
      spell_count: 1,
      targets: TargetCodec.encode(Target.unit(target_guid))
    }

    done = Message.CmsgUseItem.handle(message, state, fn _id -> context.spell end)
    assert done.character.internal.casting == nil
    assert done.character.internal.cooldowns == state.character.internal.cooldowns
    assert ItemStore.get(context.item.object.guid).item.stack_count == 3
    assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgCastResult{result: 2, reason: 0x67}}}
  end

  defp bandages(_context) do
    guid = System.unique_integer([:positive, :monotonic])

    item =
      ItemStore.create(%ItemTemplate{entry: 998_410, stackable: 20, spellid_1: 18_610, spellcharges_1: -1},
        owner: guid,
        stack_count: 3
      )

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: %Player{inv1: item.object.guid},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{health: 100, max_health: 3000, level: 60, class: 1, race: 1, auras: []}
    }

    on_exit(fn -> ItemStore.delete(item.object.guid) end)

    %{
      item: item,
      state: %State{ready: true, guid: guid, packed_guid: BinaryUtils.pack_guid(guid), character: character},
      spell: %Spell{
        id: 18_610,
        mechanic: 16,
        duration_ms: 8000,
        attributes: MapSet.new([:channeled]),
        effects: [%Effect{type: :apply_aura, aura: :periodic_heal, implicit_target_a: :target_ally}]
      }
    }
  end

  defp lockout do
    %Spell{
      id: 11_196,
      duration_ms: 60_000,
      attributes: MapSet.new([:negative]),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :mechanic_immunity, misc_value: 16}]
    }
  end
end
