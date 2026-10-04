@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Order Consumption (261 - 262)'
define view entity ZI_SCEOrderConsumption
  as select from zsce_event
{
  key order_uuid                                                                    as OrderUUID,
      // 262 reverses a 261 the game refused (live bot), so a retried order counts once
      sum( case mvt_type when '262' then 0 - mineral_value else mineral_value end ) as ConsumedMinerals,
      sum( case mvt_type when '262' then 0 - gas_value else gas_value end )         as ConsumedGas
}
where
     mvt_type = '261'
  or mvt_type = '262'
group by
  order_uuid
