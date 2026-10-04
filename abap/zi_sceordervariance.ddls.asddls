@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Production Order Variance'
define view entity ZI_SCEOrderVariance
  as select from    zsce_prodord           as Ord
    inner join      zsce_material          as Material    on Material.matnr = Ord.matnr
    left outer join ZI_SCEOrderConsumption as Consumption on Consumption.OrderUUID = Ord.order_uuid
{
  key Ord.order_uuid                                                        as OrderUUID,
      Material.build_seconds                                                as StandardSeconds,
      // live: ReleasedAt = queued in the game (STARTED); replay: back-computed, so always 0 variance
      case Ord.order_status when 'CONFIRMED'
        then Ord.confirmed_at - Ord.released_at end                         as LeadSeconds,
      case Ord.order_status when 'CONFIRMED'
        then Ord.confirmed_at - Ord.released_at - Material.build_seconds end as TimeVarianceSeconds,
      // nothing consumed before STARTED, so RELEASED stays blank instead of showing -standard
      case when Ord.order_status = 'STARTED' or Ord.order_status = 'CONFIRMED'
        then coalesce( Consumption.ConsumedMinerals, 0 ) - Material.mineral_cost end as MineralVariance,
      case when Ord.order_status = 'STARTED' or Ord.order_status = 'CONFIRMED'
        then coalesce( Consumption.ConsumedGas, 0 ) - Material.gas_cost end         as GasVariance,
      // CANCELLED / SCRAPPED never deliver: what they consumed (261 - 262) is scrap; live orders stay blank
      case when Ord.order_status = 'CANCELLED' or Ord.order_status = 'SCRAPPED'
        then coalesce( Consumption.ConsumedMinerals, 0 ) end                        as ScrapMinerals,
      case when Ord.order_status = 'CANCELLED' or Ord.order_status = 'SCRAPPED'
        then coalesce( Consumption.ConsumedGas, 0 ) end                             as ScrapGas
}
