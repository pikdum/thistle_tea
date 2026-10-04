defmodule ThistleTea.Game.Core.AI.AreaTriggerScript.BlackrockSpire do
  @moduledoc """
  vmangos `at_blackrock_spire` and `at_ubrs_the_beast`, the Blackrock Spire
  triggers that open the way up and wake The Beast
  (`InstanceScript.BlackrockSpire`).

  A player carrying the Seal of Ascension who reaches the Dragonspine Door
  starts its braziers and opens Upper Blackrock Spire for the copy. Anyone
  entering The Beast's furnace draws it out to fight, unless it is already
  fighting.
  """

  @behaviour ThistleTea.Game.Core.AI.AreaTriggerScript

  alias ThistleTea.Game.Core.AI.AreaTriggerScript
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Condition

  @dragonspine_door 2_046
  @the_beast_furnace 2_066

  @seal_of_ascension 12_344
  @ubrs_door_field 5
  @done 3

  @the_beast 10_430
  @beast_reach 100

  @impl AreaTriggerScript
  def triggers, do: [@dragonspine_door, @the_beast_furnace]

  @impl AreaTriggerScript
  def steps(@dragonspine_door, _position) do
    [
      %ScriptStep{
        command: :set_instance_data,
        datalong: @ubrs_door_field,
        datalong2: @done,
        condition: %Condition{type: :item, value1: @seal_of_ascension, value2: 1}
      }
    ]
  end

  def steps(@the_beast_furnace, _position) do
    [
      %ScriptStep{
        command: :attack_start,
        target_type: :nearest_creature_with_entry,
        target_param1: @the_beast,
        target_param2: @beast_reach,
        swap_final?: true,
        condition: %Condition{type: :in_combat, reverse?: true, swap_targets?: true}
      }
    ]
  end
end
