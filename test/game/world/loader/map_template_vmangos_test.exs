defmodule ThistleTea.Game.World.Loader.MapTemplateVmangosTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.InstanceScript
  alias ThistleTea.Game.World.Loader.MapTemplate

  @moduletag :vmangos_db

  test "loads Stratholme's audited script registration" do
    MapTemplate.init()
    MapTemplate.load_all()

    assert MapTemplate.dungeon?(329)
    assert MapTemplate.admission_policy(329).player_limit == 5
    assert MapTemplate.admission_policy(309).player_limit == 20
    assert MapTemplate.admission_policy(309).raid?
    assert MapTemplate.admission_policy(409).player_limit == 40
    assert MapTemplate.reset_days(249) == 5
    assert MapTemplate.reset_days(309) == 3
    assert MapTemplate.reset_days(409) == 7
    assert MapTemplate.instance_script_name(329) == "instance_stratholme"
    assert InstanceScript.registered_fields("instance_stratholme") == Enum.to_list(0..8)
    assert InstanceScript.initial_value("instance_stratholme", 7) == {:ok, 0}
    assert InstanceScript.initial_value("instance_stratholme", 5) == {:ok, 0}
  end
end
