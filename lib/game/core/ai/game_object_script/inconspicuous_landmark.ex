defmodule ThistleTea.Game.Core.AI.GameObjectScript.InconspicuousLandmark do
  @moduledoc """
  vmangos `go_inconspicuous_landmark`: digging at the Inconspicuous Landmark
  on Lost Rigger Cove in Tanaris during Cuergo's Gold (2882) brings five
  treasure hunters down on the player, and they carry Cuergo's Key to the
  treasure. Three are a pirate, a swashbuckler, and a buccaneer; the other
  two are any of the three. They leave after a little over five minutes
  unless killed first.

  vmangos keeps the landmark closed for ten minutes after the pirates come.
  Here it closes for the five minutes its template gives it.
  """

  @behaviour ThistleTea.Game.Core.AI.GameObjectScript

  alias ThistleTea.Game.Core.AI.GameObjectScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @landmark 142_189
  @pirate 7_899
  @swashbuckler 7_901
  @buccaneer 7_902
  @despawn_ms 310_000
  @attack_user 8
  @timed_or_dead_despawn 1
  @pirate_script 1
  @swashbuckler_script 2
  @buccaneer_script 3
  @one_in_three 33

  @pirates [
    {@pirate, {-10_119.85, -4_068.36, 4.55, 1.35}},
    {@swashbuckler, {-10_109.80, -4_054.45, 5.64, 3.17}},
    {@buccaneer, {-10_127.80, -4_047.04, 4.50, 5.07}}
  ]
  @stragglers [
    {-10_113.952148, -4_040.484375, 5.174251, 4.300828},
    {-10_136.779297, -4_063.175049, 4.787039, 0.526417}
  ]

  @impl GameObjectScript
  def entries, do: [@landmark]

  @impl GameObjectScript
  def steps(@landmark, _position) do
    Enum.map(@pirates, fn {entry, position} -> pirate(entry, position) end) ++
      Enum.map(@stragglers, &straggler/1)
  end

  defp straggler(position) do
    %ScriptStep{
      command: :start_script,
      datalong: @pirate_script,
      dataint: @one_in_three,
      datalong2: @swashbuckler_script,
      dataint2: @one_in_three,
      datalong3: @buccaneer_script,
      dataint3: 100 - 2 * @one_in_three,
      sub_scripts: %{
        @pirate_script => [pirate(@pirate, position)],
        @swashbuckler_script => [pirate(@swashbuckler, position)],
        @buccaneer_script => [pirate(@buccaneer, position)]
      }
    }
  end

  defp pirate(entry, position) do
    %ScriptStep{
      command: :summon_creature,
      datalong: entry,
      datalong2: @despawn_ms,
      dataint3: @attack_user,
      dataint4: @timed_or_dead_despawn,
      position: position
    }
  end
end
