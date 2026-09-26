defmodule ThistleTea.Game.Entity.Logic.Effects.MovementTypes do
  @moduledoc false

  effects = [
    {:BindHome, [:binder_guid], []},
    {:Charge, [:target_guid], [attack_on_arrival?: false]},
    {:ClientControlChanged, [:allow_movement?], []},
    {:MovementStopped, [], []},
    {:MovementInform, [:motion_type, :point_id], []},
    {:MovementSpeedChanged, [:speed], [movement_type: :run_speed]},
    {:MovementRootChanged, [:rooted?], []},
    {:FeatherFallChanged, [:enabled?], []},
    {:HoverChanged, [:enabled?], []},
    {:Knockback, [:cos_angle, :sin_angle, :horizontal_speed, :vertical_speed], []},
    {:WaterWalkChanged, [:enabled?], []},
    {:MonsterMove, [:move_opts], []},
    {:CreatureTeleported, [:world, :from_position, :position, :movement_block, :script_id, :declared_map_id, :options],
     []},
    {:Teleport, [:position], []},
    {:TeleportToWorld, [:world, :position], [preserve_combat?: false, orientation: nil]},
    {:TeleportNearCaster, [:caster_position, :caster_orientation, :destination], []},
    {:TeleportHome, [], []},
    {:Leap, [:position], []},
    {:TeleportToSpellTarget, [:spell_id], []},
    {:ChargeResolved, [:path, :duration_ms, :destination], [attack_target: nil, swing_delay_ms: 0]},
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
