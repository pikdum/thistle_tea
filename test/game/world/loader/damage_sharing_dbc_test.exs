defmodule ThistleTea.Game.World.Loader.DamageSharingDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.DamageSharing
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.World.Loader.Spell

  @moduletag :dbc_db

  describe "loaded damage-sharing amounts" do
    test "both Sacrifice ranks and Soul Link use the resolved aura amount exactly once" do
      target = %Character{
        object: %Object{guid: 1},
        unit: %Unit{level: 60, health: 1_000, max_health: 1_000},
        internal: %Internal{},
        player: %Player{}
      }

      for {id, amount} <- [{6940, 45}, {20_729, 55}, {25_228, 30}] do
        spell = Spell.load(id)
        {target, _} = Aura.apply_spell(target, 2, 60, spell, 0)

        assert {remaining, [%Effects.SharedDamage{damage: ^amount, spell: ^spell}]} =
                 DamageSharing.split(target, 100, :physical, 1_000, damage_sharing_targets: MapSet.new([2]))

        assert remaining == 100 - amount
      end
    end
  end
end
