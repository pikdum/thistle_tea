defmodule ItemTemplate do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:entry, :integer, autogenerate: false}

  schema "item_template" do
    field(:class, :integer, default: 0)
    field(:subclass, :integer, default: 0)
    field(:name, :string, default: "")
    field(:display_id, :integer, default: 0, source: :displayid)
    field(:quality, :integer, default: 0)
    field(:flags, :integer, default: 0)
    field(:buy_count, :integer, default: 1, source: :BuyCount)
    field(:buy_price, :integer, default: 0, source: :BuyPrice)
    field(:sell_price, :integer, default: 0, source: :SellPrice)
    field(:inventory_type, :integer, default: 0, source: :InventoryType)
    field(:allowable_class, :integer, default: -1, source: :AllowableClass)
    field(:allowable_race, :integer, default: -1, source: :AllowableRace)
    field(:item_level, :integer, default: 0, source: :ItemLevel)
    field(:required_level, :integer, default: 0, source: :RequiredLevel)
    field(:required_skill, :integer, default: 0, source: :RequiredSkill)
    field(:required_skill_rank, :integer, default: 0, source: :RequiredSkillRank)
    field(:required_spell, :integer, default: 0, source: :requiredspell)
    field(:required_honor_rank, :integer, default: 0, source: :requiredhonorrank)
    field(:required_city_rank, :integer, default: 0, source: :RequiredCityRank)
    field(:required_reputation_faction, :integer, default: 0, source: :RequiredReputationFaction)
    field(:required_reputation_rank, :integer, default: 0, source: :RequiredReputationRank)
    field(:max_count, :integer, default: 0, source: :maxcount)
    field(:stackable, :integer, default: 1)
    field(:container_slots, :integer, default: 0, source: :ContainerSlots)
    field(:stat_type1, :integer, default: 0)
    field(:stat_value1, :integer, default: 0)
    field(:stat_type2, :integer, default: 0)
    field(:stat_value2, :integer, default: 0)
    field(:stat_type3, :integer, default: 0)
    field(:stat_value3, :integer, default: 0)
    field(:stat_type4, :integer, default: 0)
    field(:stat_value4, :integer, default: 0)
    field(:stat_type5, :integer, default: 0)
    field(:stat_value5, :integer, default: 0)
    field(:stat_type6, :integer, default: 0)
    field(:stat_value6, :integer, default: 0)
    field(:stat_type7, :integer, default: 0)
    field(:stat_value7, :integer, default: 0)
    field(:stat_type8, :integer, default: 0)
    field(:stat_value8, :integer, default: 0)
    field(:stat_type9, :integer, default: 0)
    field(:stat_value9, :integer, default: 0)
    field(:stat_type10, :integer, default: 0)
    field(:stat_value10, :integer, default: 0)
    field(:dmg_min1, :float, default: 0.0)
    field(:dmg_max1, :float, default: 0.0)
    field(:dmg_type1, :integer, default: 0)
    field(:dmg_min2, :float, default: 0.0)
    field(:dmg_max2, :float, default: 0.0)
    field(:dmg_type2, :integer, default: 0)
    field(:dmg_min3, :float, default: 0.0)
    field(:dmg_max3, :float, default: 0.0)
    field(:dmg_type3, :integer, default: 0)
    field(:dmg_min4, :float, default: 0.0)
    field(:dmg_max4, :float, default: 0.0)
    field(:dmg_type4, :integer, default: 0)
    field(:dmg_min5, :float, default: 0.0)
    field(:dmg_max5, :float, default: 0.0)
    field(:dmg_type5, :integer, default: 0)
    field(:armor, :integer, default: 0)
    field(:holy_res, :integer, default: 0)
    field(:fire_res, :integer, default: 0)
    field(:nature_res, :integer, default: 0)
    field(:frost_res, :integer, default: 0)
    field(:shadow_res, :integer, default: 0)
    field(:arcane_res, :integer, default: 0)
    field(:delay, :integer, default: 1000)
    field(:ammo_type, :integer, default: 0)
    field(:ranged_mod_range, :float, default: 0.0, source: :RangedModRange)
    field(:spellid_1, :integer, default: 0)
    field(:spelltrigger_1, :integer, default: 0)
    field(:spellcharges_1, :integer, default: 0)
    field(:spellppm_rate_1, :float, default: 0.0, source: :spellppmRate_1)
    field(:spellcooldown_1, :integer, default: -1)
    field(:spellcategory_1, :integer, default: 0)
    field(:spellcategorycooldown_1, :integer, default: -1)
    field(:spellid_2, :integer, default: 0)
    field(:spelltrigger_2, :integer, default: 0)
    field(:spellcharges_2, :integer, default: 0)
    field(:spellppm_rate_2, :float, default: 0.0, source: :spellppmRate_2)
    field(:spellcooldown_2, :integer, default: -1)
    field(:spellcategory_2, :integer, default: 0)
    field(:spellcategorycooldown_2, :integer, default: -1)
    field(:spellid_3, :integer, default: 0)
    field(:spelltrigger_3, :integer, default: 0)
    field(:spellcharges_3, :integer, default: 0)
    field(:spellppm_rate_3, :float, default: 0.0, source: :spellppmRate_3)
    field(:spellcooldown_3, :integer, default: -1)
    field(:spellcategory_3, :integer, default: 0)
    field(:spellcategorycooldown_3, :integer, default: -1)
    field(:spellid_4, :integer, default: 0)
    field(:spelltrigger_4, :integer, default: 0)
    field(:spellcharges_4, :integer, default: 0)
    field(:spellppm_rate_4, :float, default: 0.0, source: :spellppmRate_4)
    field(:spellcooldown_4, :integer, default: -1)
    field(:spellcategory_4, :integer, default: 0)
    field(:spellcategorycooldown_4, :integer, default: -1)
    field(:spellid_5, :integer, default: 0)
    field(:spelltrigger_5, :integer, default: 0)
    field(:spellcharges_5, :integer, default: 0)
    field(:spellppm_rate_5, :float, default: 0.0, source: :spellppmRate_5)
    field(:spellcooldown_5, :integer, default: -1)
    field(:spellcategory_5, :integer, default: 0)
    field(:spellcategorycooldown_5, :integer, default: -1)
    field(:bonding, :integer, default: 0)
    field(:description, :string, default: "")
    field(:page_text, :integer, default: 0, source: :PageText)
    field(:language_id, :integer, default: 0, source: :LanguageID)
    field(:page_material, :integer, default: 0, source: :PageMaterial)
    field(:start_quest, :integer, default: 0, source: :startquest)
    field(:lockid, :integer, default: 0)
    field(:material, :integer, default: 0)
    field(:sheath, :integer, default: 0)
    field(:random_property, :integer, default: 0, source: :RandomProperty)
    field(:block, :integer, default: 0)
    field(:item_set, :integer, default: 0, source: :itemset)
    field(:max_durability, :integer, default: 0, source: :MaxDurability)
    field(:area, :integer, default: 0)
    field(:map, :integer, default: 0)
    field(:bag_family, :integer, default: 0, source: :BagFamily)
    field(:disenchant_id, :integer, default: 0, source: :DisenchantID)
    field(:food_type, :integer, default: 0, source: :FoodType)
    field(:min_money_loot, :integer, default: 0, source: :minMoneyLoot)
    field(:max_money_loot, :integer, default: 0, source: :maxMoneyLoot)
    field(:duration, :integer, default: 0)
    field(:extra_flags, :integer, default: 0, source: :ExtraFlags)
  end

  def random_by_type(inventory_type) do
    query =
      from(it in ItemTemplate,
        where: it.inventory_type == ^inventory_type,
        order_by: fragment("RANDOM()"),
        limit: 1
      )

    ThistleTea.Mangos.one(query)
  end
end
