defmodule ThistleTea.Game.Entity.Logic.Aura.ObjectSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura.ObjectSync

  describe "sync/1" do
    test "derives scale from the base object scale and active auras" do
      holder = %Holder{auras: [%Aura{type: :mod_scale, amount: 50}]}
      mob = %Mob{object: %Object{base_scale_x: 1.2, scale_x: 1.2}, unit: %Unit{auras: [holder]}}

      scaled = ObjectSync.sync(mob)
      restored = ObjectSync.sync(%{scaled | unit: %{scaled.unit | auras: []}})

      assert_in_delta scaled.object.scale_x, 1.8, 0.0001
      assert restored.object.scale_x == 1.2
    end
  end
end
