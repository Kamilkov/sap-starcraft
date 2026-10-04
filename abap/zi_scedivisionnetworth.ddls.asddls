@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Division Net Worth in MIN'
define view entity ZI_SCEDivisionNetWorth
  as select from ZI_SCEEventAmount
{
  key DivisionUUID,
      cast( 'MIN' as waers )                                       as ReportingCurrency,
      // decfloat34 only inside: currency_conversion needs it for unshifted amounts, OData must not see it (4.01);
      // scrap (what a CANCELLED/SCRAPPED order consumed net of 262) comes off like in ZI_SCEDivisionFinance.NetWorth
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      cast( sum( currency_conversion(
                   amount             => cast( case when MovementType = '551' then 0 - Amount
                                                    when MovementType = '561' or MovementType = '501' then Amount
                                                    when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' )
                                                     and MovementType = '261' then 0 - Amount
                                                    when ( OrderStatus = 'CANCELLED' or OrderStatus = 'SCRAPPED' )
                                                     and MovementType = '262' then Amount
                                                    // maintenance (repair cost) comes off as well
                                                    when OrderCategory = 'PM' and MovementType = '261' then 0 - Amount
                                                    else 0 end as abap.decfloat34 ),
                   source_currency    => Currency,
                   target_currency    => cast( 'MIN' as waers ),
                   exchange_rate_date => $session.system_date,
                   exchange_rate_type => 'M',
                   error_handling     => 'SET_TO_NULL' ) ) as abap.dec( 15, 0 ) ) as NetWorthMin
}
group by
  DivisionUUID
