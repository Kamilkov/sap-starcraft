@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Division Finance per Currency'
define view entity ZI_SCEDivisionFinance
  as select from ZI_SCEEventAmount
  association [1..1] to ZI_SCEDivision as _Division on $projection.DivisionUUID = _Division.DivisionUUID
{
  key DivisionUUID,
  key Currency,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '561' then Amount else 0 end ) as Opening,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '501' then Amount else 0 end ) as Mined,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case MovementType when '551' then Amount else 0 end ) as Lost,
      // scrap: what a CANCELLED or SCRAPPED order consumed and the game did not give back (it never gets a 101)
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' ) and MovementType = '261' then Amount
                when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' ) and MovementType = '262' then 0 - Amount
                else 0 end )                                     as Scrap,
      // maintenance: what repairs consumed (maintenance orders); expense at once, the repaired asset keeps its value
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when OrderCategory = 'PM' and MovementType = '261' then Amount
                else 0 end )                                     as Maintenance,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when MovementType = '561' or MovementType = '501' then Amount
                when MovementType = '551'                        then 0 - Amount
                when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' ) and MovementType = '261' then 0 - Amount
                when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' ) and MovementType = '262' then Amount
                when OrderCategory = 'PM' and MovementType = '261' then 0 - Amount
                else 0 end )                                     as NetWorth,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when Category = 'RAW' and MovementType = '261' then 0 - Amount
                when Category = 'RAW'                          then Amount
                else 0 end )                                     as OnHand,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when Category = 'RAW'                             then 0
                when MovementType = '551'                         then 0 - Amount
                when MovementType = '561' or MovementType = '101' then Amount
                else 0 end )                                     as Assets,
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when Category = 'UNIT' and MovementType = '551' then 0 - Amount
                when Category = 'UNIT' and ( MovementType = '561' or MovementType = '101' ) then Amount
                else 0 end )                                     as Army,
      // scrapped orders left WIP for Scrap above, maintenance orders never enter it
      @Semantics.amount.currencyCode: 'Currency'
      sum( case when OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' then 0
                when OrderCategory = 'PM'                         then 0
                when MovementType = '261'                         then Amount
                when MovementType = '262' or MovementType = '101' then 0 - Amount
                else 0 end )                                     as WIP,
      _Division
}
group by
  DivisionUUID,
  Currency
