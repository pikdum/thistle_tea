defmodule ThistleTea.Game.Entity.Data.Component.Internal.Goober do
  @moduledoc false

  defstruct quest_id: 0,
            event_id: 0,
            page_id: 0,
            gossip_id: 0,
            spell_id: 0,
            auto_close_ms: 0,
            cooldown_ms: 0,
            custom_animation?: false,
            consumable?: false,
            ready_at: nil,
            depleted?: false
end
