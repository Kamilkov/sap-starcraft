@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Movement gas in MIN (rate M)'
define view entity ZI_SCEMovementValue
  as select from ZI_SCEMovementAnalysis
{
  key EventUUID,
      MineralCurrency,
      // own view: CDS forbids amount + number, get_numeric_value only takes an element; decfloat34 never reaches OData
      @Semantics.amount.currencyCode: 'MineralCurrency'
      currency_conversion( amount             => cast( Gas as abap.decfloat34 ),
                           source_currency    => GasCurrency,
                           target_currency    => MineralCurrency,
                           exchange_rate_date => $session.system_date,
                           exchange_rate_type => 'M',
                           error_handling     => 'SET_TO_NULL' ) as GasInMin
}
