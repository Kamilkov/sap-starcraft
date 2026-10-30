@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Division Army Value in MIN'
define view entity ZI_SCEDivisionArmyValue
  as select from ZI_SCEEventAmount
{
  key DivisionUUID,
      // army = units that are not workers: opening (561) and built (101) count, lost (551) comes off;
      // same MIN valuation as ZI_SCEDivisionNetWorth (rate M, GAS -> MIN), decfloat34 only inside
      cast( sum( currency_conversion(
                   amount             => cast( case when MovementType = '551' then 0 - Amount
                                                    else Amount end as abap.decfloat34 ),
                   source_currency    => Currency,
                   target_currency    => cast( 'MIN' as waers ),
                   exchange_rate_date => $session.system_date,
                   exchange_rate_type => 'M',
                   error_handling     => 'SET_TO_NULL' ) ) as abap.dec( 15, 0 ) ) as ArmyValueMin
}
where
      Category = 'UNIT'
  and Material <> 'SCV'
  and Material <> 'Probe'
  and ( MovementType = '561' or MovementType = '101' or MovementType = '551' )
group by
  DivisionUUID
