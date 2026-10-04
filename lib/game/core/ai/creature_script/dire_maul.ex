defmodule ThistleTea.Game.Core.AI.CreatureScript.DireMaul do
  @moduledoc """
  vmangos `npc_mizzle_the_crafty`, Mizzle the Crafty in Dire Maul North.

  King Gordok's death calls Mizzle (`InstanceScript.DireMaul`). He hails the
  new king and walks up to the throne, where he offers to talk once he gets
  there. vmangos runs his C++ AI instead of his database events, so the
  database's walk-in event never runs and neither does it here.
  """

  @behaviour ThistleTea.Game.Core.AI.CreatureScript

  alias ThistleTea.Game.Core.AI.CreatureScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @mizzle 14_353
  @throne {816.30, 481.80, 37.30, 3.17}
  @hail_the_king 9_348
  @at_the_throne 9_411

  @home_motion 7
  @npc_flags_field 147
  @gossip 0x1
  @add_flags 1

  @impl CreatureScript
  def entries, do: [@mizzle]

  @impl CreatureScript
  def events(@mizzle = entry) do
    [
      CreatureScript.event(entry, 1, :spawned, [
        %ScriptStep{command: :set_home_position, position: @throne},
        %ScriptStep{command: :movement, datalong: @home_motion},
        talk(@hail_the_king)
      ]),
      CreatureScript.event(
        entry,
        2,
        :reached_home,
        [
          talk(@at_the_throne),
          %ScriptStep{command: :modify_flags, datalong: @npc_flags_field, datalong2: @gossip, datalong3: @add_flags}
        ],
        repeatable?: false
      )
    ]
  end

  defp talk(text_id), do: %ScriptStep{command: :talk, dataint: text_id}
end
