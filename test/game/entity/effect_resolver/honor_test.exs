defmodule ThistleTea.Game.Entity.EffectResolver.HonorTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Honor.Damage
  alias ThistleTea.Game.Entity.EffectResolver.Honor
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member
  alias ThistleTea.Game.WorldRef

  describe "resolve/2" do
    test "captures a pet's owner before the pet disappears" do
      pet = Guid.from_low_guid(:pet, 1, 1)
      effect = %Effects.HonorDamage{source_guid: pet, damage: 10, now: 100, lethal?: false, honorless?: false}

      assert [%Effects.HonorContribution{player_guid: 7}] =
               Honor.resolve(effect, metadata: fn ^pet -> %{owner_guid: 7} end)

      assert [%Effects.HonorContribution{player_guid: nil}] = Honor.resolve(effect, metadata: fn ^pet -> nil end)
    end
  end

  describe "shares/4" do
    test "shares battleground team damage with the nearby living roster using raid scaling" do
      world = WorldRef.instance(489, 1)

      victim = %Character{
        unit: %Unit{race: 2},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      history = %Damage{by_player: %{0 => 20, 1 => 40, 9 => 40}, last_damage_at: 100}

      opts = [
        participants: fn ^world -> Map.new(1..10, &{&1, %{team: :alliance}}) end,
        group_of: fn _guid -> flunk("battleground membership supplies the group") end,
        metadata: fn guid -> %{race: 1, alive?: guid != 9} end,
        position: fn
          10 -> {world, 75.0, 0.0, 0.0}
          _guid -> {world, 1.0, 0.0, 0.0}
        end
      ]

      shares = Honor.shares(victim, history, 100, opts)
      assert Enum.sort(Map.keys(shares)) == Enum.to_list(1..8)
      for {_guid, share} <- shares, do: assert_in_delta(share, 0.8 * 0.6 / 8, 0.0001)
    end

    test "shares group damage with living nearby members, retaining ineligible damage in the denominator" do
      world = WorldRef.open(0)

      victim = %Character{
        unit: %Unit{race: 2},
        internal: %Internal{world: world},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }

      group = %Group{id: 10, members: Enum.map(1..5, &%Member{guid: &1})}
      history = %Damage{by_player: %{0 => 20, 1 => 30, 4 => 30, 6 => 20}, last_damage_at: 100}

      opts = [
        group_of: fn guid -> if guid in 1..5, do: group end,
        metadata: fn guid -> %{race: 1, alive?: guid != 4} end,
        position: fn
          3 -> {WorldRef.instance(0, 2), 0.0, 0.0, 0.0}
          5 -> {world, 75.0, 0.0, 0.0}
          _guid -> {world, 1.0, 0.0, 0.0}
        end
      ]

      assert Honor.shares(victim, history, 100, opts) == %{1 => 0.3, 2 => 0.3, 6 => 0.2}
      assert Honor.shares(victim, history, 60_101, opts) == %{}
    end
  end
end
