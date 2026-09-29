defmodule ThistleTea.Game.World.Inbound.Spell do
  @moduledoc "Handles decoded spell casting, aura, talent, and skill client messages."

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity.Player.Professions
  alias ThistleTea.Game.World.Entity.Player.Spellcasting
  alias ThistleTea.Game.World.Entity.Player.Spells
  alias ThistleTea.Game.World.Entity.Player.Talents

  require Logger

  def messages do
    [
      Message.CmsgCancelAura,
      Message.CmsgCancelAutoRepeatSpell,
      Message.CmsgCancelCast,
      Message.CmsgCancelChannelling,
      Message.CmsgCancelGrowthAura,
      Message.CmsgCastSpell,
      Message.CmsgLearnTalent,
      Message.CmsgUnlearnSkill
    ]
  end

  def handle(%Message.CmsgCancelAura{spell_id: spell_id}, state), do: Spells.cancel_aura(state, spell_id)

  def handle(%Message.CmsgCancelAutoRepeatSpell{}, state), do: Spellcasting.cancel_auto_repeat(state)

  def handle(%Message.CmsgCancelCast{}, state) do
    Logger.info("CMSG_CANCEL_CAST")
    Spellcasting.cancel_cast_request(state)
  end

  def handle(%Message.CmsgCancelChannelling{}, state), do: Spellcasting.cancel_cast_request(state)

  def handle(%Message.CmsgCancelGrowthAura{}, state), do: state

  def handle(%Message.CmsgCastSpell{spell_id: spell_id, spell_cast_targets: spell_cast_targets}, state) do
    Spellcasting.cast(state, spell_id, spell_cast_targets)
  end

  def handle(%Message.CmsgLearnTalent{talent_id: talent_id, requested_rank: requested_rank}, %{ready: true} = state) do
    Talents.learn(state, talent_id, requested_rank)
  end

  def handle(%Message.CmsgLearnTalent{}, state), do: state

  def handle(%Message.CmsgUnlearnSkill{skill_id: skill_id}, %{ready: true, character: %Character{}} = state) do
    Professions.unlearn(state, skill_id)
  end

  def handle(%Message.CmsgUnlearnSkill{}, state), do: state
end
