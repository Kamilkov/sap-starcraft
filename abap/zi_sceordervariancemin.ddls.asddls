@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Production Order Variance in MIN'
define view entity ZI_SCEOrderVarianceMin
  as select from ZI_SCEOrderVariance
{
  key OrderUUID,
      StandardSeconds,
      LeadSeconds,
      TimeVarianceSeconds,
      MineralVariance,
      GasVariance,
      cast( 'MIN' as waers )                                     as ReportingCurrency,
      // gas converted at rate M like Net worth (B.2.1); kept out of ZI_SCEOrderVariance because the
      // CDS test double framework does not support currency_conversion; decfloat34 only inside (OData 4.01);
      // the conversion result is cast to plain dec before adding: CDS refuses "+" on an amount
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      cast( MineralVariance
            + cast( currency_conversion( amount             => cast( GasVariance as abap.decfloat34 ),
                                         source_currency    => cast( 'GAS' as waers ),
                                         target_currency    => cast( 'MIN' as waers ),
                                         exchange_rate_date => $session.system_date,
                                         exchange_rate_type => 'M',
                                         error_handling     => 'SET_TO_NULL' ) as abap.dec( 15, 0 ) )
            as abap.dec( 15, 0 ) )                               as PriceVarianceMin,
      // scrap of a CANCELLED / SCRAPPED order, same conversion; blank for live orders
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      cast( ScrapMinerals
            + cast( currency_conversion( amount             => cast( ScrapGas as abap.decfloat34 ),
                                         source_currency    => cast( 'GAS' as waers ),
                                         target_currency    => cast( 'MIN' as waers ),
                                         exchange_rate_date => $session.system_date,
                                         exchange_rate_type => 'M',
                                         error_handling     => 'SET_TO_NULL' ) as abap.dec( 15, 0 ) )
            as abap.dec( 15, 0 ) )                               as ScrapVarianceMin
}
