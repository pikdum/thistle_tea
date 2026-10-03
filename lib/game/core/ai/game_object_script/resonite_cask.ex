defmodule ThistleTea.Game.Core.AI.GameObjectScript.ResoniteCask do
  @moduledoc """
  vmangos `go_resonite_cask`: opening the Resonite Cask in Stonetalon
  Mountains with the Enchanted Resonite Crystal raises Goggeroc beside it for
  Earthen Arise (6481). He fights whoever is near and leaves after five
  minutes out of combat.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @resonite_cask 178_145
  @goggeroc 11_920
  @despawn_ms 300_000
  @no_attack -1
  @timed_out_of_combat_despawn 4
  @contact_distance 0.5

  @impl GameObjectScript
  def entries, do: [@resonite_cask]

  @impl GameObjectScript
  def steps(@resonite_cask, {x, y, z, o}) do
    [
      %ScriptStep{
        command: :summon_creature,
        datalong: @goggeroc,
        datalong2: @despawn_ms,
        dataint3: @no_attack,
        dataint4: @timed_out_of_combat_despawn,
        position: {x + @contact_distance * :math.cos(o), y + @contact_distance * :math.sin(o), z, o}
      }
    ]
  end
end
