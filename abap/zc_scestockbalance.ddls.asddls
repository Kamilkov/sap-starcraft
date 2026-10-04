@EndUserText.label: 'SCE Stock Balance'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Stock', typeNamePlural: 'Stock balance' }
define view entity ZC_SCEStockBalance
  as select from ZI_SCEStockBalance
{
  key GameUUID,
  key DivisionUUID,
      @UI.lineItem: [{ position: 10 }]
  key PlantUUID,
      @UI.lineItem: [{ position: 20 }]
  key Material,
      @UI.lineItem: [{ position: 30 }]
      OnHand
}
