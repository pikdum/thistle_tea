defmodule ThistleTea.Game.Entity.Logic.Effects.MovementTypes do
  @moduledoc false

  effects = [
    {:BindHome, [:binder_guid], []},
    {:Charge, [:target_guid], []},
    {:MovementStopped, [], []},
    {:MovementSpeedChanged, [:speed], [movement_type: :run_speed]},
    {:MovementRootChanged, [:rooted?], []},
    {:FeatherFallChanged, [:enabled?], []},
    {:HoverChanged, [:enabled?], []},
    {:WaterWalkChanged, [:enabled?], []},
    {:MonsterMove, [:move_opts], []},
    {:CreatureTeleported, [:world, :from_position, :position, :movement_block, :script_id, :declared_map_id, :options],
     []},
    {:Teleport, [:position], []},
    {:TeleportToWorld, [:world, :position], [preserve_combat?: false]},
    {:TeleportHome, [], []},
    {:Leap, [:position], []},
    {:TeleportToSpellTarget, [:spell_id], []},
    {:ChargeResolved, [:path, :duration_ms, :destination], []},
    {:SetFacing, [:facing], []}
  ]

  for {name, required, optional} <- effects do
    defmodule Module.concat(ThistleTea.Game.Entity.Logic.Effects, name) do
      @moduledoc false
      @enforce_keys required
      defstruct required ++ optional
    end
  end
end
