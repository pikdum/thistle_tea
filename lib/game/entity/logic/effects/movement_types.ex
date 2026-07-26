defmodule ThistleTea.Game.Entity.Logic.Effects.MovementTypes do
  @moduledoc false

  effects = [
    {:Charge, [:target_guid], []},
    {:MovementStopped, [], []},
    {:MovementSpeedChanged, [:speed], []},
    {:MovementRootChanged, [:rooted?], []},
    {:FeatherFallChanged, [:enabled?], []},
    {:HoverChanged, [:enabled?], []},
    {:WaterWalkChanged, [:enabled?], []},
    {:MonsterMove, [:move_opts], []},
    {:Teleport, [:position], []},
    {:TeleportToWorld, [:world, :position], []},
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
