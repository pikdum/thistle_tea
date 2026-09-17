defmodule ThistleTea.Game.Entity.Logic.PeriodicCombatTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.PlayerCombat
  alias ThistleTea.Game.Entity.Logic.PowerBurn
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:player]

  describe "take_damage/4" do
    test "periodic damage refreshes the victim's combat window and blocks health regeneration", %{player: player} do
      player = PlayerCombat.mark_attacked(player, 0)
      player = Core.take_damage(player, 10, 4_000, source: 2, periodic: true)
      {player, _} = PlayerCombat.sync(player, %Blackboard{}, 5_000)
      assert player.internal.in_combat
      assert player.internal.last_hostile_time == 4_000
      assert Regen.tick(player, 6_000).unit.health == 90
      {player, _} = PlayerCombat.sync(player, %Blackboard{}, 9_000)
      refute player.internal.in_combat
    end

    test "environmental and self damage do not establish combat", %{player: player} do
      for opts <- [[environmental?: true], [source: 1]] do
        player = Core.take_damage(player, 10, 4_000, opts)
        refute player.internal.in_combat
      end
    end
  end

  describe "receive/4" do
    test "harmful spell feedback refreshes the caster even for fully absorbed ticks", %{player: player} do
      spell = %Spell{id: 24_619}
      payload = %{victim_guid: 2, proc_type: :deal_harmful_periodic, damage: 0, outcome: :normal}
      player = SpellFeedback.receive(player, payload, spell, 4_000)
      assert player.internal.in_combat
      assert player.internal.last_hostile_time == 4_000
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
    test "zero-damage burns refresh combat only when power is consumed", %{player: player} do
      context = %CastContext{caster_guid: 2, caster_level: 50}
      spell = %Spell{id: 23_153, school: :frost}
      effect = %Effect{misc_value: 0, multiple_value: 0.0}
      {player, [event]} = PowerBurn.apply(player, context, spell, 50, effect, 4_000, periodic?: true)
      assert player.unit.power1 == 0
      assert player.unit.health == 100
      assert player.internal.last_hostile_time == 4_000
      assert event.damage == 0
      assert event.proc_type == :deal_harmful_periodic
      {player, []} = PowerBurn.apply(player, context, spell, 50, effect, 6_000, periodic?: true)
      assert player.internal.last_hostile_time == 4_000
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
