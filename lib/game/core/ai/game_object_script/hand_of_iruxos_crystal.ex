defmodule ThistleTea.Game.Core.AI.GameObjectScript.HandOfIruxosCrystal do
  @moduledoc """
  vmangos `go_hand_of_iruxos_crystal`: touching the Hand of Iruxos crystal in
  Desolace with the Demon Pick calls a Demon Spirit out at the crystal for Hand
  of Iruxos (5381). The spirit attacks the player who touched the crystal and
  fades fifteen seconds after it leaves combat. Only one spirit answers at a
  time, and it carries the Demon Box.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @crystal 176_581
  @demon_spirit 11_876
  @despawn_ms 15_000
  @unique_limit 1
  @unique_distance 50
  @unique 0x04
  @attack_user 8
  @timed_out_of_combat_despawn 4

  @spirit_position {-346.84, 1_765.13, 138.39, 5.91}

  @impl GameObjectScript
  def entries, do: [@crystal]

  @impl GameObjectScript
  def steps(@crystal, _position) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @demon_spirit,
        datalong2: @despawn_ms,
        datalong3: @unique_limit,
        datalong4: @unique_distance,
        dataint: @unique,
        dataint3: @attack_user,
        dataint4: @timed_out_of_combat_despawn,
        position: @spirit_position
      }
    ]
  end
end
