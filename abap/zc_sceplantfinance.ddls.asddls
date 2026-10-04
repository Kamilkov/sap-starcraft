@EndUserText.label: 'SCE Outpost Finance'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Outpost finance', typeNamePlural: 'Outpost finance' }
@UI.presentationVariant: [
  { qualifier: 'ByPlant',
    sortOrder: [{ by: 'PlantCode', direction: #ASC }, { by: 'Currency', direction: #DESC }],
    visualizations: [{ type: #AS_LINEITEM }] } ]
define view entity ZC_SCEPlantFinance
  as select from ZI_SCEPlantFinance
{
  key PlantUUID,
  key Currency,
      DivisionUUID,
      @EndUserText.label: 'Outpost'
      @UI.lineItem: [{ position: 10 }]
      _Plant.PlantCode as PlantCode,
      @EndUserText.label: 'Opening'
      @UI.lineItem: [{ position: 20 }]
      Opening,
      @EndUserText.label: 'Produced'
      @UI.lineItem: [{ position: 30 }]
      Produced,
      @EndUserText.label: 'Lost'
      @UI.lineItem: [{ position: 40 }]
      Lost,
      @EndUserText.label: 'Net asset value'
      @UI.lineItem: [{ position: 50 }]
      NetAssetValue
}
