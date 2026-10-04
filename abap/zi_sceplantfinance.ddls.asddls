@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Outpost Finance per Currency'
define view entity ZI_SCEPlantFinance
  as select from ZI_SCEEventAmount
  association [1..1] to ZI_SCEPlant as _Plant on $projection.PlantUUID = _Plant.PlantUUID
{
  key PlantUUID,
  key Currency,
      DivisionUUID,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '561' then Amount else 0 end ) as Opening,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '101' then Amount else 0 end ) as Produced,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '551' then Amount else 0 end ) as Lost,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '561' then Amount
                             when '101' then Amount
                             when '551' then 0 - Amount
                             else 0 end )                        as NetAssetValue,
      _Plant
}
where
  PlantUUID is not initial
group by
  PlantUUID,
  Currency,
  DivisionUUID
