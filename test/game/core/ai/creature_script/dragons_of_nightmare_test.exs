defmodule ThistleTea.Game.Core.AI.CreatureScript.DragonsOfNightmareTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.AI.BT.Context.Perception
  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.EventAI
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  @ysondre 14_887
  @lethon 14_888
  @taerar 14_890
  @dream_fog 15_224
  @shade_of_taerar 15_302
  @not_selectable 0x02000000

  describe "events/1" do
    test "every dragon marks the players around it on the pull" do
      for entry <- [@ysondre, @lethon, 14_889, @taerar] do
        assert %{actions: [[%ScriptStep{command: :cast_spell, datalong: 25_041, datalong2: 0x22} | _talk]]} =
                 Enum.find(CreatureScript.events(entry), &(&1.event_type == :aggro))
      end
    end

    test "an evade ends every dragon's pending scripts" do
      for entry <- [@ysondre, @lethon, 14_889, @taerar] do
        assert %{actions: [[%ScriptStep{command: :stop_scripts} | _rest]]} =
                 Enum.find(CreatureScript.events(entry), &(&1.event_type == :evade))
      end
    end

    test "Ysondre summons druid spirits for every few players on her threat list" do
      for {players, druids} <- [{2, 3}, {8, 6}, {25, 15}] do
        guids = Enum.map(1..players, fn _ -> Guid.from_low_guid(:player, Unique.integer()) end)
        ysondre = dragon(@ysondre, threat: guids)

        {ysondre, _blackboard} = EventAI.tick(ysondre, Blackboard.new(), 1_000, context(ysondre, guids))

        summons = Enum.filter(ysondre.internal.events, &match?(%Effects.SummonCreature{}, &1))
        assert length(summons) == druids
        assert Enum.all?(summons, &(&1.summon.entry == 15_260 and &1.summon.attack_guid in guids))
      end
    end

    test "Lethon raises a spirit shade where Draw Spirit strikes a player" do
      player = Guid.from_low_guid(:player, Unique.integer())
      lethon = dragon(@lethon, threat: [player])
      context = context(lethon, [player])

      {lethon, _blackboard} =
        EventAI.on_spell_hit_target(lethon, Blackboard.new(), player, 24_811, 0x20, 1_000, context)

      assert [%Effects.SummonCreature{summon: %{entry: 15_261, position: {10.0, 20.0, 30.0, _o}}}] =
               lethon.internal.events
    end

    test "Taerar banishes himself until his three shades fall" do
      player = Guid.from_low_guid(:player, Unique.integer())
      taerar = dragon(@taerar, threat: [player])
      context = context(taerar, [player])

      {taerar, blackboard} = EventAI.tick(taerar, Blackboard.new(), 1_000, context)

      assert blackboard.event_ai.phase == 1
      assert Bitwise.band(taerar.unit.flags, @not_selectable) != 0

      shades = for %Effects.TriggerSpell{spell_id: id} <- taerar.internal.events, id in 24_841..24_843, do: id
      assert Enum.sort(shades) == [24_841, 24_842, 24_843]

      {taerar, blackboard} = shade_dies(taerar, blackboard, context)
      assert blackboard.event_ai.phase == 2
      assert Bitwise.band(taerar.unit.flags, @not_selectable) != 0

      {taerar, blackboard} = shade_dies(taerar, blackboard, context)
      {taerar, blackboard} = shade_dies(taerar, blackboard, context)
      assert blackboard.event_ai.phase == 0
      assert Bitwise.band(taerar.unit.flags, @not_selectable) == 0
    end

    test "Taerar's two-minute timeout only ends the banishment that started it" do
      taerar = dragon(@taerar)
      context = context(taerar, [])

      {_taerar, blackboard} = timeout(taerar, banished(2), 1, context)
      assert blackboard.event_ai.phase == 0

      {_taerar, blackboard} = timeout(taerar, banished(4), 1, context)
      assert blackboard.event_ai.phase == 4
    end

    test "Dream Fog drifts to another player on its owner's threat list" do
      [tank, other] = Enum.map(1..2, fn _ -> Guid.from_low_guid(:player, Unique.integer()) end)
      owner = Guid.from_low_guid(:mob, @ysondre, Unique.integer())
      fog = fog(owner, tank)
      observations = %{owner => %Observation{guid: owner, metadata: %{combat_targets: [tank, other]}}}
      context = Context.new(1_000, perception: Perception.new(1_000, nil, observations, %{}))

      {fog, _blackboard} = EventAI.tick(fog, Blackboard.new(), 1_000, context)

      assert [%Effects.StartAttack{target_guid: ^other}] = fog.internal.events
    end
  end

  defp shade_dies(taerar, blackboard, context) do
    shade = Guid.from_low_guid(:pet, @shade_of_taerar, Unique.integer())

    event = %SummonEvent{
      event: :summoned_just_died,
      entry: @shade_of_taerar,
      world: taerar.internal.world,
      observation: %Observation{guid: shade}
    }

    EventAI.on_summon_event(taerar, blackboard, event, context)
  end

  defp timeout(taerar, blackboard, banishment, context),
    do: EventAI.on_script_event(taerar, blackboard, 1, banishment, taerar.object.guid, 1_000, context)

  defp banished(phase) do
    blackboard = Blackboard.new()
    %{blackboard | event_ai: %{blackboard.event_ai | phase: phase}}
  end

  defp context(%Mob{object: %Object{guid: guid}}, players) do
    observations =
      Map.new(players, fn player ->
        {player, %Observation{guid: player, position: {WorldRef.open(0), 10.0, 20.0, 30.0}, metadata: %{alive?: true}}}
      end)

    observations = Map.put(observations, guid, %Observation{guid: guid, metadata: %{}})
    Context.new(1_000, perception: Perception.new(1_000, nil, observations, %{}))
  end

  defp dragon(entry, opts \\ []) do
    threat = Map.new(Keyword.get(opts, :threat, []), &{&1, 100})

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, entry, Unique.integer()), entry: entry},
      unit: %Unit{health: 70, max_health: 100, level: 63, auras: [], flags: 0, faction_template: 50},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 1.5}},
      internal: %Internal{
        world: WorldRef.open(0),
        in_combat: true,
        threat: threat,
        creature: %Creature{ai_events: CreatureScript.events(entry)},
        spellbook: %{24_883 => self_stun()}
      }
    }
  end

  defp fog(owner, victim) do
    %Mob{
      object: %Object{guid: Guid.from_low_guid(:pet, @dream_fog, Unique.integer()), entry: @dream_fog},
      unit: %Unit{health: 100, max_health: 100, level: 63, auras: [], flags: 0, target: victim},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{
        world: WorldRef.open(0),
        in_combat: true,
        pet: %Pet{owner_guid: owner, kind: :guardian},
        creature: %Creature{ai_events: Enum.reject(CreatureScript.events(@dream_fog), &(&1.event_type == :spawned))},
        spellbook: %{}
      }
    }
  end

  defp self_stun do
    %Spell{
      id: 24_883,
      name: "Self Stun",
      school: :physical,
      cast_time_ms: 0,
      range_yards: 0.0,
      mana_cost: 0,
      power_type: 0,
      attributes: MapSet.new(),
      effects: []
    }
  end
end
