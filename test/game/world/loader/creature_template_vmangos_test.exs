defmodule ThistleTea.Game.World.Loader.CreatureTemplateVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.CreatureTemplate
  alias ThistleTea.Game.World.Loader.CreatureTemplate, as: CreatureTemplateLoader

  @moduletag :vmangos_db

  @spirit_healer 6_491

  setup do
    CreatureTemplateLoader.init()
    saved = :ets.take(CreatureTemplateLoader, @spirit_healer)
    on_exit(fn -> :ets.insert(CreatureTemplateLoader, saved) end)
    :ok
  end

  describe "get/1" do
    test "queries spirit healers as ghost visible without leaking static flags" do
      assert %CreatureTemplate{type_flags: 0x02} = CreatureTemplateLoader.get(@spirit_healer)
    end
  end
end
