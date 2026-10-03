defmodule ThistleTea.Game.Core.Aura.PeriodicTriggerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "tick/2" do
    test "pulses as aura-triggered spells so an idle Azuregos engages nobody" do
      azuregos = %Mob{
        object: %Object{guid: Unique.integer(), entry: 6109},
        unit: %Unit{health: 100, max_health: 100, level: 63, auras: []},
        internal: %Internal{world: %WorldRef{map_id: 1}}
      }

      pulse =
        Semantics.compile(%Spell{
          id: 23_184,
          duration_ms: -1,
          effects: [
            %Effect{
              index: 0,
              type: :apply_aura,
              aura: :periodic_trigger_spell,
              trigger_spell_id: 23_183,
              amplitude_ms: 10_000,
              implicit_target_a: :caster
            }
          ]
        })

      context = %CastContext{caster_guid: azuregos.object.guid, caster_level: 63}
      {azuregos, _events} = Aura.apply_spell(azuregos, context, pulse, 0)
      {_azuregos, events} = Aura.tick(azuregos, 10_000)

      assert [%Effects.TriggerSpell{spell_id: 23_183, triggering_spell_id: 23_184}] =
               Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
    end
  end
end
