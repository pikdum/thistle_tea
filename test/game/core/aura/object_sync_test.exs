defmodule ThistleTea.Game.Core.Aura.ObjectSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Aura.ObjectSync
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob

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
