defmodule ThistleTea.Game.Entity.Logic.ItemSpellTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.Resurrection
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:entities]

  describe "receive/4" do
    test "Six Demon Bag preserves every outcome's chance, caster, recipient, and item", %{context: context} do
      target = %Mob{object: %Object{guid: 2}, unit: %Unit{health: 100, auras: []}, internal: %Internal{}}
      spell = %Spell{id: 14_537, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :target_enemy}]}
      assert {^target, [%RandomChoice{} = choice]} = SpellEffect.receive(target, context, spell, 0)
      assert RandomChoice.total_weight(choice) == 100

      outcomes =
        for roll <- 1..100 do
          assert [%Effects.TriggerSpell{source_guid: 1, cast_item_guid: 42, resolve_targets?: true} = trigger] =
                   RandomChoice.select(choice, roll)

          {trigger.spell_id, trigger.target_guid}
        end

      assert Enum.frequencies(outcomes) == %{
               {11_921, 2} => 25,
               {13_322, 2} => 25,
               {21_179, 2} => 20,
               {13_323, 2} => 7,
               {13_323, 1} => 3,
               {25_189, 2} => 15,
               {14_642, 1} => 5
             }

      second = %{spell | effects: [%{hd(spell.effects) | index: 1}]}
      assert {^target, []} = SpellEffect.receive(target, context, second, 0)
      dead = %{target | unit: %{target.unit | health: 0}}
      assert {^dead, []} = SpellEffect.receive(dead, context, spell, 0)
    end

    test "cables select success before recording any pending resurrection", %{character: character, context: context} do
      for {id, chance, failure_id} <- [{8342, 33, 8338}, {22_999, 50, 23_055}] do
        spell = %Spell{
          id: id,
          effects: [%Effect{index: 0, type: :resurrect, base_points: 14, base_dice: 1, die_sides: 1}]
        }

        assert {^character, [%RandomChoice{} = choice]} = SpellEffect.receive(character, context, spell, 0)
        assert RandomChoice.total_weight(choice) == 100

        for roll <- 1..chance do
          assert [%Effects.OfferResurrection{health: 150, mana: 120, spell: %{id: ^id}}] =
                   RandomChoice.select(choice, roll)
        end

        for roll <- (chance + 1)..100 do
          assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, cast_item_guid: 42, spell_id: ^failure_id}] =
                   RandomChoice.select(choice, roll)
        end

        offered = EventSink.emit(character, RandomChoice.select(choice, chance), Context.new(self()))
        assert offered.internal.pending_resurrect.health == 150
        assert offered.internal.pending_resurrect.mana == 120
        assert offered.internal.pending_resurrect.position == context.caster_position
        assert_receive {:"$gen_cast", {:send_packet, %Message.SmsgResurrectRequest{guid: 1}}}
        assert EventSink.emit(offered, RandomChoice.select(choice, 1), Context.new(self())) == offered
        refute_received {:"$gen_cast", {:send_packet, %Message.SmsgResurrectRequest{}}}

        alive = %{character | unit: %{character.unit | health: 1}}
        assert EventSink.emit(alive, RandomChoice.select(choice, 1), Context.new(self())) == alive
        refute_received {:"$gen_cast", {:send_packet, %Message.SmsgResurrectRequest{}}}
        assert {^alive, []} = SpellEffect.receive(alive, context, spell, 0)
      end
    end
  end

  describe "request/5" do
    test "ordinary resurrection still creates its offer immediately", %{character: character, context: context} do
      {offered, [%Effects.ResurrectRequest{}]} = Resurrection.request(character, context, %Spell{id: 2006}, 70, 135)
      assert offered.internal.pending_resurrect.health == 70
      assert offered.internal.pending_resurrect.mana == 135
    end
  end

  defp entities(_context) do
    character = %Character{
      object: %Object{guid: 2},
      unit: %Unit{health: 0, max_health: 1_000, max_power1: 800, auras: []},
      player: %Player{flags: 0},
      internal: %Internal{}
    }

    context = %CastContext{
      caster_guid: 1,
      caster_level: 60,
      caster_position: {WorldRef.open(0), 1.0, 2.0, 3.0},
      caster_orientation: 1.5,
      target_guid: 2,
      cast_item_guid: 42
    }

    %{character: character, context: context}
  end
end
