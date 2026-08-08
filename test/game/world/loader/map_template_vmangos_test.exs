defmodule ThistleTea.Game.World.Loader.MapTemplateVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.InstanceScript
  alias ThistleTea.Game.World.Loader.MapTemplate

  @moduletag :vmangos_db

  test "loads Stratholme's audited script registration" do
    MapTemplate.init()
    MapTemplate.load_all()

    assert MapTemplate.dungeon?(329)
    assert MapTemplate.instance_script_name(329) == "instance_stratholme"
    assert InstanceScript.registered_fields("instance_stratholme") == [7]
    assert InstanceScript.initial_value("instance_stratholme", 7) == {:ok, 0}
    assert InstanceScript.initial_value("instance_stratholme", 5) == {:error, {:unsupported_field, 5}}
  end
end
