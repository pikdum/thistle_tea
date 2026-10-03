defmodule ThistleTea.Game.Core.AI.EventScriptTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.EventScript
  alias ThistleTea.Game.Core.AI.ScriptStep

  @toxicologist 12_319

  describe "steps_by_event/0" do
    test "drawing the poisoned well's water calls three toxicologists on the player" do
      steps = EventScript.steps_by_event()[5_246]

      assert [
               {331.52, -2_270.94, 242.21, 5.15},
               {332.09, -2_291.26, 241.86, 1.05},
               {345.97, -2_282.66, 241.77, 3.16}
             ] = Enum.map(steps, & &1.position)

      assert Enum.all?(
               steps,
               &match?(
                 %ScriptStep{
                   command: :summon_creature,
                   datalong: @toxicologist,
                   datalong2: 120_000,
                   dataint3: 8,
                   dataint4: 1
                 },
                 &1
               )
             )
    end
  end

  describe "summon_entries/0" do
    test "lists every creature a ported event or its summons call" do
      assert Enum.sort(EventScript.summon_entries()) == [4_100, 4_490, @toxicologist]
    end
  end
end
