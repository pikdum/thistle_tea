defmodule ThistleTea.Game.Core.Combat.PeriodicCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.BT.Blackboard
  alias ThistleTea.Game.Core.AI.BT.Context
  alias ThistleTea.Game.Core.Combat.PlayerCombat
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Power.PowerBurn
  alias ThistleTea.Game.Core.Power.Regen
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellFeedback
  alias ThistleTea.Game.Core.WorldRef

  setup [:player]

  describe "take_damage/4" do
    test "channeled damage refreshes the victim's combat window and blocks health regeneration", %{player: player} do
      spell = %Spell{id: 10_797, attributes: MapSet.new([:channeled])}
      player = PlayerCombat.mark_attacked(player, 0)
      player = Entity.take_damage(player, 10, 4_000, source: 2, periodic: true, spell: spell)
      {player, _} = PlayerCombat.sync(player, %Blackboard{}, Context.new(5_000))
      assert player.internal.in_combat
      assert player.internal.last_hostile_time == 4_000
      assert Regen.tick(player, 6_000).unit.health == 90
      {player, _} = PlayerCombat.sync(player, %Blackboard{}, Context.new(9_000))
      refute player.internal.in_combat
    end

    test "ordinary periodic damage does not restart or refresh combat", %{player: player} do
      refute Entity.take_damage(player, 10, 4_000, source: 2, periodic: true).internal.in_combat
      player = PlayerCombat.mark_attacked(player, 0)
      player = Entity.take_damage(player, 10, 4_000, source: 2, periodic: true)
      assert player.internal.last_hostile_time == 0
      {player, _} = PlayerCombat.sync(player, %Blackboard{}, Context.new(5_000))
      refute player.internal.in_combat
    end

    test "environmental and self damage do not establish combat", %{player: player} do
      for opts <- [[environmental?: true], [source: 1]] do
        player = Entity.take_damage(player, 10, 4_000, opts)
        refute player.internal.in_combat
      end
    end
  end

  describe "receive/4" do
    test "proc feedback leaves combat to the resolved contact", %{player: player} do
      spell = %Spell{id: 24_619}
      payload = %{victim_guid: 2, proc_type: :deal_harmful_periodic, damage: 0, outcome: :normal}
      player = SpellFeedback.receive(player, payload, spell, 4_000)
      refute player.internal.in_combat
    end

    test "healing and feedback after death do not establish combat", %{player: player} do
      payload = %{victim_guid: 2, proc_type: :deal_helpful_spell, damage: 10, outcome: :normal}
      refute SpellFeedback.receive(player, payload, %Spell{id: 1}, 4_000).internal.in_combat
      player = %{player | unit: %{player.unit | health: 0}}
      payload = %{payload | proc_type: :deal_harmful_periodic}
      refute SpellFeedback.receive(player, payload, %Spell{id: 1}, 4_000).internal.in_combat
    end
  end

  describe "apply/7" do
    test "zero-damage periodic burns do not restart combat", %{player: player} do
      context = %CastContext{caster_guid: 2, caster_level: 50}
      spell = %Spell{id: 23_153, school: :frost}
      effect = %Effect{misc_value: 0, multiple_value: 0.0}
      {player, [event]} = PowerBurn.apply(player, context, spell, 50, effect, 4_000, periodic?: true)
      assert player.unit.power1 == 0
      assert player.unit.health == 100
      refute player.internal.in_combat
      assert event.damage == 0
      assert event.proc_type == :deal_harmful_periodic
      {player, []} = PowerBurn.apply(player, context, spell, 50, effect, 6_000, periodic?: true)
      refute player.internal.in_combat
    end
  end

  defp player(_context) do
    %{
      player: %Character{
        object: %Object{guid: 1},
        player: %Player{},
        unit: %Unit{
          health: 100,
          max_health: 100,
          level: 50,
          class: 8,
          spirit: 100,
          power_type: 0,
          power1: 50,
          max_power1: 50,
          auras: []
        },
        internal: %Internal{world: WorldRef.open(0), in_combat: false}
      }
    }
  end
end
