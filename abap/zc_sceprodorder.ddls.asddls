@EndUserText.label: 'SCE Production Order'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Production Order', typeNamePlural: 'Production Orders', title: { value: 'Material' } }
define view entity ZC_SCEProdOrder
  as projection on ZI_SCEProdOrder
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key OrderUUID,
      DivisionUUID,
      PlantUUID,
      GameUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 10 },
                     { type: #FOR_ACTION, dataAction: 'cancelOrder', label: 'Cancel Order' }]
      @UI.identification: [{ position: 10 }]
      Material,
      @EndUserText.label: 'Quantity'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      Quantity,
      @EndUserText.label: 'Status'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      OrderStatus,
      @UI.lineItem: [{ position: 35 }]
      @UI.identification: [{ position: 35 }]
      @EndUserText.label: 'Bot message'
      StatusText,
      @EndUserText.label: 'Released at (s)'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      ReleasedAt,
      @EndUserText.label: 'Confirmed at (s)'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      ConfirmedAt,
      @EndUserText.label: 'Unit tag'
      @UI.identification: [{ position: 55 }]
      UnitTag,
      // order variances: time against the standard build time, price against the material master (gas at rate M)
      @EndUserText.label: 'Std time (s)'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      _Variance.StandardSeconds     as StandardSeconds,
      @EndUserText.label: 'Lead time (s)'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      _Variance.LeadSeconds         as LeadSeconds,
      @EndUserText.label: 'Time variance (s)'
      @UI.lineItem: [{ position: 80 }]
      @UI.identification: [{ position: 80 }]
      _Variance.TimeVarianceSeconds as TimeVarianceSeconds,
      _Variance.ReportingCurrency   as ReportingCurrency,
      @EndUserText.label: 'Price variance (MIN)'
      @UI.lineItem: [{ position: 90 }]
      @UI.identification: [{ position: 90 }]
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      _Variance.PriceVarianceMin    as PriceVarianceMin,
      @EndUserText.label: 'Scrap variance (MIN)'
      @UI.lineItem: [{ position: 95 }]
      @UI.identification: [{ position: 95 }]
      @Semantics.amount.currencyCode: 'ReportingCurrency'
      _Variance.ScrapVarianceMin    as ScrapVarianceMin,
      _Division : redirected to parent ZC_SCEDivision,
      _Plant    : redirected to ZC_SCEPlant,
      _Material : redirected to ZC_SCEMaterial,
      _Game     : redirected to ZC_SCEGame
}
