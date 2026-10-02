defmodule ThistleTea.Game.Core.AI.CreatureScript.TwilightCorrupterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @corrupter 15_625

  describe "events/1" do
    test "shouts on the pull" do
      assert %{event_type: :aggro, actions: [[%ScriptStep{command: :talk, dataint: 11_269}]]} = event(:aggro)
    end

    test "wracks the room with Soul Corruption and charms a random player with Creature of Nightmare" do
      assert [soul_corruption, creature_of_nightmare] =
               Enum.filter(CreatureScript.events(@corrupter), &(&1.event_type == :timer_in_combat))

      assert %{
               param1: 6_000,
               param2: 18_000,
               param3: 20_000,
               param4: 30_000,
               actions: [[%ScriptStep{command: :cast_spell, datalong: 25_805, target_self?: true}]]
             } = soul_corruption

      assert %{
               param1: 10_000,
               param2: 20_000,
               param3: 35_000,
               param4: 40_000,
               actions: [
                 [
                   %ScriptStep{
                     command: :cast_spell,
                     datalong: 25_806,
                     target_type: :hostile_random,
                     target_param1: 0x02
                   }
                 ]
               ]
             } = creature_of_nightmare
    end

    test "swallows the soul of each player it kills" do
      corrupter = corrupter()
      player = Guid.from_low_guid(:player, Unique.integer())
      creature = Guid.from_low_guid(:mob, 1_380, Unique.integer())

      self = corrupter.object.guid

      {fed, _blackboard} = EventAI.on_kill(corrupter, Blackboard.new(), player, 0, Context.new(0))

      assert [
               %Effects.MonsterTalk{chat_type: :text_emote, target_guid: ^player},
               %Effects.TriggerSpell{spell_id: 21_307, source_guid: ^self, target_guid: ^self}
             ] = fed.internal.events

      {unfed, _blackboard} = EventAI.on_kill(corrupter, Blackboard.new(), creature, 0, Context.new(0))
      assert unfed.internal.events == []
    end
  end

  defp resolve_texts(event) do
    actions =
      Enum.map(event.actions, fn steps ->
        Enum.map(steps, fn
          %ScriptStep{command: :talk, dataint: 11_270} = step ->
            %{step | texts: [%{text: "%s swallows their soul.", chat_type: :text_emote, language: 0, emote_id: 0}]}

          step ->
            step
        end)
      end)

    %{event | actions: actions}
  end

  defp event(type), do: Enum.find(CreatureScript.events(@corrupter), &(&1.event_type == type))

  defp corrupter do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, @corrupter, Unique.integer()), entry: @corrupter},
      unit: %Unit{health: 50_000, max_health: 50_000, level: 63, auras: [], flags: 0, faction_template: 14},
      movement_block: %MovementBlock{position: {-10_335.9, -489.051, 50.6233, 2.59373}},
      internal: %Internal{
        world: WorldRef.open(0),
        name: "Twilight Corrupter",
        creature: %Creature{ai_events: Enum.map(CreatureScript.events(@corrupter), &resolve_texts/1)},
        spellbook: %{}
      }
    }
  end
end
