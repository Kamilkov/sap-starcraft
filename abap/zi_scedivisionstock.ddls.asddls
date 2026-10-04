@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Division Stock (all plants)'
define view entity ZI_SCEDivisionStock
  as select from ZI_SCEStockBalance
{
  key DivisionUUID,
  key Material,
      sum( OnHand ) as OnHand
}
group by
  DivisionUUID,
  Material
